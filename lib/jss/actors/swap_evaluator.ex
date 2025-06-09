defmodule JSS.Actors.SwapEvaluator do
  @moduledoc """
  Acteur GenServer spécialisé dans l'évaluation des swaps de commandes.
  Calcule les impacts globaux et maintient un cache pour les performances.
  """

  use GenServer
  require Logger

  alias JSS.Core.SharedPlanningState
  alias JSS.Optimization.CostCalculator
  alias JSS.System.ParameterManager

  @type swap_key :: {String.t(), String.t()}
  @type evaluation_result :: %{
    delta_score: float(),
    breakdown: map(),
    confidence: float(),
    timestamp: DateTime.t()
  }

  defstruct [
    :current_state,
    :evaluation_cache,
    :pending_evaluations,
    :statistics,
    :cache_config
  ]

  # Configuration du cache
  @default_cache_config %{
    max_size: 1000,
    ttl_seconds: 30,
    cleanup_interval: 60_000  # 1 minute
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Évalue l'impact d'un swap de commandes.
  Retourne immédiatement si en cache, sinon évalue de manière asynchrone.
  """
  def evaluate_swap(order_a_id, order_b_id, reply_to \\ self()) do
    GenServer.cast(__MODULE__, {:evaluate_swap, order_a_id, order_b_id, reply_to})
  end

  @doc """
  Évalue un swap de manière synchrone (pour les cas urgents).
  """
  def evaluate_swap_sync(order_a_id, order_b_id, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:evaluate_swap_sync, order_a_id, order_b_id}, timeout)
  end

  @doc """
  Met à jour l'état de planification courant.
  Invalide les caches obsolètes.
  """
  def update_planning_state(new_state) do
    GenServer.cast(__MODULE__, {:update_planning_state, new_state})
  end

  @doc """
  Force le nettoyage du cache.
  """
  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  @doc """
  Récupère les statistiques de performance.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  # Callbacks GenServer

  @impl true
  def init(opts) do
    # Abonnement aux changements de paramètres
    ParameterManager.subscribe()

    # Configuration du cache depuis les paramètres
    cache_config = load_cache_config()

    # Planification du nettoyage périodique
    schedule_cache_cleanup(cache_config.cleanup_interval)

    initial_state = %__MODULE__{
      current_state: nil,
      evaluation_cache: %{},
      pending_evaluations: %{},
      statistics: %{
        cache_hits: 0,
        cache_misses: 0,
        evaluations_completed: 0,
        evaluations_failed: 0,
        avg_evaluation_time_ms: 0.0
      },
      cache_config: cache_config
    }

    Logger.info("SwapEvaluator started with cache config: #{inspect(cache_config)}")

    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:evaluate_swap, order_a_id, order_b_id, reply_to}, state) do
    swap_key = normalize_swap_key(order_a_id, order_b_id)

    case get_cached_evaluation(state, swap_key) do
      {:hit, result} ->
        # Cache hit - réponse immédiate
        send(reply_to, {:swap_evaluation_complete, swap_key, result})
        updated_stats = %{state.statistics | cache_hits: state.statistics.cache_hits + 1}
        {:noreply, %{state | statistics: updated_stats}}

      :miss ->
        # Cache miss - évaluation asynchrone
        case state.current_state do
          nil ->
            send(reply_to, {:swap_evaluation_failed, swap_key, :no_planning_state})
            {:noreply, state}

          planning_state ->
            # Démarrage de l'évaluation en arrière-plan
            task_ref = start_evaluation_task(planning_state, order_a_id, order_b_id, reply_to)

            updated_pending = Map.put(state.pending_evaluations, task_ref, {
              swap_key, reply_to, DateTime.utc_now()
            })

            updated_stats = %{state.statistics | cache_misses: state.statistics.cache_misses + 1}

            {:noreply, %{state |
              pending_evaluations: updated_pending,
              statistics: updated_stats
            }}
        end
    end
  end

  @impl true
  def handle_call({:evaluate_swap_sync, order_a_id, order_b_id}, _from, state) do
    swap_key = normalize_swap_key(order_a_id, order_b_id)

    case get_cached_evaluation(state, swap_key) do
      {:hit, result} ->
        updated_stats = %{state.statistics | cache_hits: state.statistics.cache_hits + 1}
        {:reply, {:ok, result}, %{state | statistics: updated_stats}}

      :miss ->
        case state.current_state do
          nil ->
            {:reply, {:error, :no_planning_state}, state}

          planning_state ->
            # Évaluation synchrone
            start_time = System.monotonic_time(:millisecond)

            result = case CostCalculator.calculate_swap_impact(planning_state, order_a_id, order_b_id) do
              {:ok, delta_score, breakdown} ->
                evaluation_result = %{
                  delta_score: delta_score,
                  breakdown: breakdown,
                  confidence: 1.0,  # Évaluation complète
                  timestamp: DateTime.utc_now()
                }

                # Mise en cache
                updated_cache = cache_evaluation(state, swap_key, evaluation_result)
                updated_state = %{state | evaluation_cache: updated_cache}

                {:ok, evaluation_result, updated_state}

              {:error, reason} ->
                {:error, reason, state}
            end

            case result do
              {:ok, eval_result, new_state} ->
                # Mise à jour des statistiques
                evaluation_time = System.monotonic_time(:millisecond) - start_time
                updated_stats = update_evaluation_stats(new_state.statistics, evaluation_time, :success)

                {:reply, {:ok, eval_result}, %{new_state | statistics: updated_stats}}

              {:error, reason, error_state} ->
                evaluation_time = System.monotonic_time(:millisecond) - start_time
                updated_stats = update_evaluation_stats(error_state.statistics, evaluation_time, :failure)

                {:reply, {:error, reason}, %{error_state | statistics: updated_stats}}
            end
        end
    end
  end

  @impl true
  def handle_cast({:update_planning_state, new_state}, state) do
    # Invalidation du cache quand l'état change
    cleaned_cache = invalidate_cache_entries(state.evaluation_cache, new_state)

    {:noreply, %{state |
      current_state: new_state,
      evaluation_cache: cleaned_cache
    }}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    Logger.info("SwapEvaluator cache cleared manually")
    {:noreply, %{state | evaluation_cache: %{}}}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    enhanced_stats = Map.merge(state.statistics, %{
      cache_size: map_size(state.evaluation_cache),
      pending_evaluations: map_size(state.pending_evaluations),
      cache_hit_ratio: calculate_cache_hit_ratio(state.statistics)
    })

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_info({:evaluation_complete, task_ref, result}, state) do
    case Map.pop(state.pending_evaluations, task_ref) do
      {nil, _} ->
        # Tâche inconnue ou déjà traitée
        {:noreply, state}

      {{swap_key, reply_to, start_time}, updated_pending} ->
        evaluation_time = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

        case result do
          {:ok, evaluation_result} ->
            # Mise en cache du résultat
            updated_cache = cache_evaluation(state, swap_key, evaluation_result)

            # Notification du demandeur
            send(reply_to, {:swap_evaluation_complete, swap_key, evaluation_result})

            # Mise à jour des statistiques
            updated_stats = update_evaluation_stats(state.statistics, evaluation_time, :success)

            {:noreply, %{state |
              evaluation_cache: updated_cache,
              pending_evaluations: updated_pending,
              statistics: updated_stats
            }}

          {:error, reason} ->
            # Notification d'erreur
            send(reply_to, {:swap_evaluation_failed, swap_key, reason})

            # Mise à jour des statistiques d'erreur
            updated_stats = update_evaluation_stats(state.statistics, evaluation_time, :failure)

            {:noreply, %{state |
              pending_evaluations: updated_pending,
              statistics: updated_stats
            }}
        end
    end
  end

  @impl true
  def handle_info(:cache_cleanup, state) do
    # Nettoyage périodique du cache
    cleaned_cache = cleanup_expired_cache_entries(state)

    # Reprogrammation du nettoyage
    schedule_cache_cleanup(state.cache_config.cleanup_interval)

    Logger.debug("Cache cleanup completed. Entries: #{map_size(cleaned_cache)}")

    {:noreply, %{state | evaluation_cache: cleaned_cache}}
  end

  @impl true
  def handle_info({:parameter_updated, "optimizer", param_name, _new_value}, state) when param_name in ["swap_cache_size", "swap_cache_ttl"] do
    # Rechargement de la configuration du cache
    new_cache_config = load_cache_config()

    # Nettoyage si la taille max a diminué
    cleaned_cache = if new_cache_config.max_size < state.cache_config.max_size do
      trim_cache_to_size(state.evaluation_cache, new_cache_config.max_size)
    else
      state.evaluation_cache
    end

    {:noreply, %{state |
      cache_config: new_cache_config,
      evaluation_cache: cleaned_cache
    }}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Fonctions privées

  defp normalize_swap_key(order_a_id, order_b_id) do
    # Normalisation pour éviter les doublons (a,b) et (b,a)
    if order_a_id <= order_b_id do
      {order_a_id, order_b_id}
    else
      {order_b_id, order_a_id}
    end
  end

  defp get_cached_evaluation(state, swap_key) do
    case Map.get(state.evaluation_cache, swap_key) do
      nil -> :miss
      cached_result ->
        # Vérification de l'expiration
        now = DateTime.utc_now()
        age_seconds = DateTime.diff(now, cached_result.timestamp, :second)

        if age_seconds <= state.cache_config.ttl_seconds do
          {:hit, cached_result}
        else
          :miss
        end
    end
  end

  defp start_evaluation_task(planning_state, order_a_id, order_b_id, reply_to) do
    parent_pid = self()

    spawn_link(fn ->
      result = CostCalculator.calculate_swap_impact(planning_state, order_a_id, order_b_id)

      case result do
        {:ok, delta_score, breakdown} ->
          evaluation_result = %{
            delta_score: delta_score,
            breakdown: breakdown,
            confidence: 1.0,
            timestamp: DateTime.utc_now()
          }

          send(parent_pid, {:evaluation_complete, make_ref(), {:ok, evaluation_result}})

        {:error, reason} ->
          send(parent_pid, {:evaluation_complete, make_ref(), {:error, reason}})
      end
    end)
  end

  defp cache_evaluation(state, swap_key, evaluation_result) do
    new_cache = Map.put(state.evaluation_cache, swap_key, evaluation_result)

    # Vérification de la taille maximale du cache
    if map_size(new_cache) > state.cache_config.max_size do
      trim_cache_to_size(new_cache, state.cache_config.max_size)
    else
      new_cache
    end
  end

  defp trim_cache_to_size(cache, max_size) do
    if map_size(cache) <= max_size do
      cache
    else
      # Suppression des entrées les plus anciennes
      sorted_entries =
        cache
        |> Enum.sort_by(fn {_key, result} -> result.timestamp end, DateTime)
        |> Enum.take(max_size)
        |> Map.new()

      sorted_entries
    end
  end

  defp invalidate_cache_entries(cache, new_state) do
    # Pour simplifier, on invalide tout le cache quand l'état change
    # Une approche plus sophistiquée invaliderait seulement les entrées affectées

    # Si le changement est mineur (ex: juste une mise à jour de timestamp),
    # on pourrait garder certaines entrées
    case cache_invalidation_strategy() do
      :full_invalidation -> %{}
      :selective_invalidation -> selective_cache_invalidation(cache, new_state)
    end
  end

  defp cache_invalidation_strategy do
    ParameterManager.get("optimizer", "cache_invalidation_strategy") || :full_invalidation
  end

  defp selective_cache_invalidation(cache, _new_state) do
    # Implementation future : invalidation sélective basée sur les changements
    # Pour l'instant, invalidation complète par sécurité
    %{}
  end

  defp cleanup_expired_cache_entries(state) do
    now = DateTime.utc_now()
    ttl_seconds = state.cache_config.ttl_seconds

    state.evaluation_cache
    |> Enum.filter(fn {_key, result} ->
      age_seconds = DateTime.diff(now, result.timestamp, :second)
      age_seconds <= ttl_seconds
    end)
    |> Map.new()
  end

  defp update_evaluation_stats(stats, evaluation_time_ms, result_type) do
    new_count = case result_type do
      :success -> stats.evaluations_completed + 1
      :failure -> stats.evaluations_failed + 1
    end

    # Calcul de la moyenne mobile du temps d'évaluation
    total_evaluations = stats.evaluations_completed + stats.evaluations_failed + 1
    new_avg_time = ((stats.avg_evaluation_time_ms * (total_evaluations - 1)) + evaluation_time_ms) / total_evaluations

    case result_type do
      :success ->
        %{stats |
          evaluations_completed: new_count,
          avg_evaluation_time_ms: new_avg_time
        }
      :failure ->
        %{stats |
          evaluations_failed: new_count,
          avg_evaluation_time_ms: new_avg_time
        }
    end
  end

  defp calculate_cache_hit_ratio(stats) do
    total_requests = stats.cache_hits + stats.cache_misses

    if total_requests > 0 do
      (stats.cache_hits / total_requests) * 100.0
    else
      0.0
    end
  end

  defp load_cache_config do
    %{
      max_size: ParameterManager.get("optimizer", "swap_cache_size") || @default_cache_config.max_size,
      ttl_seconds: ParameterManager.get("optimizer", "swap_cache_ttl") || @default_cache_config.ttl_seconds,
      cleanup_interval: @default_cache_config.cleanup_interval
    }
  end

  defp schedule_cache_cleanup(interval_ms) do
    Process.send_after(self(), :cache_cleanup, interval_ms)
  end

  @doc """
  Évalue plusieurs swaps en parallèle pour les algorithmes qui en ont besoin.
  """
  def evaluate_multiple_swaps(swap_list, timeout \\ 10_000) do
    GenServer.call(__MODULE__, {:evaluate_multiple_swaps, swap_list}, timeout)
  end

  @doc """
  Préchauffe le cache avec des swaps fréquemment utilisés.
  """
  def preheat_cache(order_ids) do
    GenServer.cast(__MODULE__, {:preheat_cache, order_ids})
  end

  # Callbacks supplémentaires pour les nouvelles fonctionnalités

  @impl true
  def handle_call({:evaluate_multiple_swaps, swap_list}, _from, state) do
    case state.current_state do
      nil ->
        {:reply, {:error, :no_planning_state}, state}

      planning_state ->
        # Évaluation en parallèle de tous les swaps
        start_time = System.monotonic_time(:millisecond)

        results =
          swap_list
          |> Task.async_stream(fn {order_a_id, order_b_id} ->
            swap_key = normalize_swap_key(order_a_id, order_b_id)

            case get_cached_evaluation(state, swap_key) do
              {:hit, cached_result} ->
                {swap_key, {:cached, cached_result}}

              :miss ->
                case CostCalculator.calculate_swap_impact(planning_state, order_a_id, order_b_id) do
                  {:ok, delta_score, breakdown} ->
                    evaluation_result = %{
                      delta_score: delta_score,
                      breakdown: breakdown,
                      confidence: 1.0,
                      timestamp: DateTime.utc_now()
                    }
                    {swap_key, {:evaluated, evaluation_result}}

                  {:error, reason} ->
                    {swap_key, {:error, reason}}
                end
            end
          end, timeout: 5000, max_concurrency: 4)
          |> Enum.map(fn {:ok, result} -> result end)

        # Mise en cache des nouveaux résultats
        new_cache =
          results
          |> Enum.reduce(state.evaluation_cache, fn
            {swap_key, {:evaluated, result}}, cache_acc ->
              Map.put(cache_acc, swap_key, result)
            _, cache_acc ->
              cache_acc
          end)

        evaluation_time = System.monotonic_time(:millisecond) - start_time

        # Mise à jour des statistiques
        successful_evaluations = Enum.count(results, fn {_, result} ->
          match?({:evaluated, _}, result) or match?({:cached, _}, result)
        end)

        updated_stats = %{state.statistics |
          evaluations_completed: state.statistics.evaluations_completed + successful_evaluations,
          avg_evaluation_time_ms: (state.statistics.avg_evaluation_time_ms + evaluation_time) / 2
        }

        {:reply, {:ok, results}, %{state |
          evaluation_cache: new_cache,
          statistics: updated_stats
        }}
    end
  end

  @impl true
  def handle_cast({:preheat_cache, order_ids}, state) do
    case state.current_state do
      nil ->
        {:noreply, state}

      planning_state ->
        # Génération de toutes les combinaisons possibles de swaps
        swap_combinations =
          for order_a <- order_ids,
              order_b <- order_ids,
              order_a < order_b,
              do: {order_a, order_b}

        # Évaluation asynchrone des swaps non mis en cache
        Enum.each(swap_combinations, fn {order_a_id, order_b_id} ->
          swap_key = normalize_swap_key(order_a_id, order_b_id)

          case get_cached_evaluation(state, swap_key) do
            :miss ->
              # Démarrage d'une évaluation asynchrone
              start_evaluation_task(planning_state, order_a_id, order_b_id, self())

            {:hit, _} ->
              # Déjà en cache, rien à faire
              :ok
          end
        end)

        Logger.info("Cache preheating started for #{length(swap_combinations)} swap combinations")
        {:noreply, state}
    end
  end

  @doc """
  Fonction utilitaire pour diagnostiquer les performances du cache.
  """
  def diagnose_cache_performance do
    GenServer.call(__MODULE__, :diagnose_cache_performance)
  end

  @impl true
  def handle_call(:diagnose_cache_performance, _from, state) do
    diagnosis = %{
      cache_config: state.cache_config,
      cache_size: map_size(state.evaluation_cache),
      pending_evaluations: map_size(state.pending_evaluations),
      statistics: state.statistics,
      cache_hit_ratio: calculate_cache_hit_ratio(state.statistics),
      cache_utilization: (map_size(state.evaluation_cache) / state.cache_config.max_size) * 100.0,
      oldest_cache_entry: get_oldest_cache_entry_age(state.evaluation_cache),
      cache_memory_estimate: estimate_cache_memory_usage(state.evaluation_cache)
    }

    {:reply, diagnosis, state}
  end

  defp get_oldest_cache_entry_age(cache) do
    if map_size(cache) == 0 do
      0
    else
      now = DateTime.utc_now()
      oldest_timestamp =
        cache
        |> Map.values()
        |> Enum.map(& &1.timestamp)
        |> Enum.min(DateTime)

      DateTime.diff(now, oldest_timestamp, :second)
    end
  end

  defp estimate_cache_memory_usage(cache) do
    # Estimation approximative en bytes
    map_size(cache) * 500  # ~500 bytes par entrée de cache
  end
end
