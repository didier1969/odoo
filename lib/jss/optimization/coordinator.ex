defmodule JSS.Optimization.Coordinator do
  @moduledoc """
  Coordinateur central du cycle d'optimisation.
  Gère la séquence stricte des algorithmes avec timeout et handover d'état.
  """

  use GenServer
  require Logger

  alias JSS.Core.SharedPlanningState
  alias JSS.Optimization.{CostCalculator, SimulatedAnnealing}
  alias JSS.Actors.SwapEvaluator
  alias JSS.System.ParameterManager

  @type algorithm_name :: :simulated_annealing | :vns | :hybrid
  @type coordinator_status :: :idle | :running | :paused | :stopping

  defstruct [
    :shared_state,
    :algorithm_cycle,
    :current_algorithm_index,
    :current_algorithm_pid,
    :current_timer_ref,
    :cycle_number,
    :coordinator_status,
    :algorithm_statistics,
    :performance_history,
    :emergency_stop_reason
  ]

  # Configuration par défaut
  @default_algorithm_cycle [:simulated_annealing, :vns, :hybrid]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Démarre le cycle d'optimisation avec un état de planification initial.
  """
  def start_optimization(initial_state) do
    GenServer.call(__MODULE__, {:start_optimization, initial_state})
  end

  @doc """
  Arrête le cycle d'optimisation de manière gracieuse.
  """
  def stop_optimization(reason \\ :manual_stop) do
    GenServer.call(__MODULE__, {:stop_optimization, reason})
  end

  @doc """
  Met en pause le cycle d'optimisation.
  """
  def pause_optimization do
    GenServer.call(__MODULE__, :pause_optimization)
  end

  @doc """
  Reprend le cycle d'optimisation après une pause.
  """
  def resume_optimization do
    GenServer.call(__MODULE__, :resume_optimization)
  end

  @doc """
  Force le passage à l'algorithme suivant.
  """
  def force_next_algorithm do
    GenServer.cast(__MODULE__, :force_next_algorithm)
  end

  @doc """
  Récupère l'état actuel du coordinateur.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Récupère les statistiques détaillées.
  """
  def get_detailed_statistics do
    GenServer.call(__MODULE__, :get_detailed_statistics)
  end

  @doc """
  Met à jour l'état de planification depuis l'extérieur.
  """
  def update_planning_state(new_state, reason \\ :external_update) do
    GenServer.cast(__MODULE__, {:update_planning_state, new_state, reason})
  end

  @doc """
  Redémarre un nouveau cycle d'optimisation après arrêt.
  """
  def restart_optimization_cycle do
    GenServer.call(__MODULE__, :restart_cycle)
  end

  # Callbacks GenServer

  @impl true
  def init(opts) do
    # Abonnement aux changements de paramètres
    ParameterManager.subscribe()

    # Configuration initiale
    algorithm_cycle = Keyword.get(opts, :algorithm_cycle, @default_algorithm_cycle)

    initial_state = %__MODULE__{
      shared_state: nil,
      algorithm_cycle: algorithm_cycle,
      current_algorithm_index: 0,
      current_algorithm_pid: nil,
      current_timer_ref: nil,
      cycle_number: 0,
      coordinator_status: :idle,
      algorithm_statistics: %{},
      performance_history: [],
      emergency_stop_reason: nil
    }

    Logger.info("OptimizationCoordinator started with algorithm cycle: #{inspect(algorithm_cycle)}")

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:start_optimization, initial_planning_state}, _from, state) do
    if state.coordinator_status != :idle do
      {:reply, {:error, :already_running}, state}
    else
      case validate_planning_state(initial_planning_state) do
        :ok ->
          # Initialisation de l'état et démarrage du premier algorithme
          updated_state = %{state |
            shared_state: initial_planning_state,
            current_algorithm_index: 0,
            cycle_number: 1,
            coordinator_status: :running,
            algorithm_statistics: initialize_algorithm_stats(),
            performance_history: []
          }

          case start_current_algorithm(updated_state) do
            {:ok, new_state} ->
              Logger.info("Optimization cycle started - Cycle ##{new_state.cycle_number}")
              {:reply, :ok, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, %{updated_state | coordinator_status: :idle}}
          end

        {:error, reason} ->
          {:reply, {:error, {:invalid_planning_state, reason}}, state}
      end
    end
  end

  @impl true
  def handle_call({:stop_optimization, reason}, _from, state) do
    case state.coordinator_status do
      :idle ->
        {:reply, {:error, :not_running}, state}

      _ ->
        # Arrêt gracieux de l'algorithme en cours
        stopped_state = stop_current_algorithm(state, reason)
        final_state = %{stopped_state |
          coordinator_status: :idle,
          emergency_stop_reason: reason
        }

        Logger.info("Optimization cycle stopped - Reason: #{reason}")
        {:reply, :ok, final_state}
    end
  end

  @impl true
  def handle_call(:pause_optimization, _from, state) do
    case state.coordinator_status do
      :running ->
        paused_state = pause_current_algorithm(state)
        {:reply, :ok, %{paused_state | coordinator_status: :paused}}

      _ ->
        {:reply, {:error, :not_running}, state}
    end
  end

  @impl true
  def handle_call(:resume_optimization, _from, state) do
    case state.coordinator_status do
      :paused ->
        resumed_state = resume_current_algorithm(state)
        {:reply, :ok, %{resumed_state | coordinator_status: :running}}

      _ ->
        {:reply, {:error, :not_paused}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    current_algorithm = get_current_algorithm_name(state)

    status = %{
      coordinator_status: state.coordinator_status,
      current_algorithm: current_algorithm,
      cycle_number: state.cycle_number,
      algorithm_index: state.current_algorithm_index,
      total_algorithms: length(state.algorithm_cycle),
      current_score: get_current_score(state),
      emergency_stop_reason: state.emergency_stop_reason
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_detailed_statistics, _from, state) do
    detailed_stats = %{
      coordinator_status: state.coordinator_status,
      cycle_number: state.cycle_number,
      algorithm_cycle: state.algorithm_cycle,
      current_algorithm_index: state.current_algorithm_index,
      algorithm_statistics: state.algorithm_statistics,
      performance_history: Enum.take(state.performance_history, 50),  # 50 dernières entrées
      shared_state_info: get_shared_state_info(state.shared_state),
      memory_usage: get_memory_usage(),
      uptime_seconds: get_uptime_seconds()
    }

    {:reply, detailed_stats, state}
  end

  @impl true
  def handle_call(:restart_cycle, _from, state) do
    case state.coordinator_status do
      :idle ->
        case state.shared_state do
          nil ->
            {:reply, {:error, :no_planning_state}, state}
          _planning_state ->
            case start_current_algorithm(%{state |
              coordinator_status: :running,
              current_algorithm_index: 0,
              cycle_number: state.cycle_number + 1
            }) do
              {:ok, new_state} ->
                Logger.info("Optimization cycle restarted - Cycle ##{new_state.cycle_number}")
                {:reply, :ok, new_state}
              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
      _ ->
        {:reply, {:error, :already_running}, state}
    end
  end

  @impl true
  def handle_cast(:force_next_algorithm, state) do
    if state.coordinator_status == :running do
      Logger.info("Forcing transition to next algorithm")
      new_state = terminate_current_and_advance(state, :forced_transition)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_planning_state, new_planning_state, reason}, state) do
    # Mise à jour de l'état partagé et notification des composants
    updated_state = %{state | shared_state: new_planning_state}

    # Notification du SwapEvaluator
    SwapEvaluator.update_planning_state(new_planning_state)

    # Notification de l'algorithme en cours si actif
    if state.current_algorithm_pid do
      send_to_current_algorithm(state, {:planning_state_updated, new_planning_state, reason})
    end

    Logger.debug("Planning state updated - Reason: #{reason}")
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:algorithm_timeout, algorithm_name}, state) do
    if get_current_algorithm_name(state) == algorithm_name and state.coordinator_status == :running do
      Logger.info("Algorithm #{algorithm_name} timeout reached")
      new_state = terminate_current_and_advance(state, :timeout)
      {:noreply, new_state}
    else
      # Timeout obsolète, ignorer
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:algorithm_complete, algorithm_name, final_state, statistics}, state) do
    if get_current_algorithm_name(state) == algorithm_name and state.coordinator_status == :running do
      Logger.info("Algorithm #{algorithm_name} completed gracefully")

      # Enregistrement des statistiques
      updated_state = record_algorithm_completion(state, algorithm_name, final_state, statistics)

      # Passage à l'algorithme suivant
      new_state = advance_to_next_algorithm(updated_state)
      {:noreply, new_state}
    else
      # Réponse obsolète ou inattendue
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:algorithm_error, algorithm_name, error_reason}, state) do
    if get_current_algorithm_name(state) == algorithm_name and state.coordinator_status == :running do
      Logger.error("Algorithm #{algorithm_name} failed: #{inspect(error_reason)}")

      # Enregistrement de l'erreur
      updated_state = record_algorithm_error(state, algorithm_name, error_reason)

      # Décision : continuer avec l'algorithme suivant ou arrêter
      case should_continue_after_error(error_reason) do
        true ->
          new_state = advance_to_next_algorithm(updated_state)
          {:noreply, new_state}

        false ->
          emergency_state = stop_current_algorithm(updated_state, {:algorithm_error, error_reason})
          final_state = %{emergency_state |
            coordinator_status: :idle,
            emergency_stop_reason: {:algorithm_error, algorithm_name, error_reason}
          }
          {:noreply, final_state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:parameter_updated, "optimizer", param_name, new_value}, state) when param_name in ["algorithm_time_budget"] do
    # Mise à jour des timeouts si l'algorithme en cours est affecté
    if state.coordinator_status == :running and state.current_timer_ref do
      # Calcul du nouveau timeout basé sur le temps déjà écoulé
      new_timeout = calculate_adjusted_timeout(new_value)

      if new_timeout > 0 do
        # Annulation de l'ancien timer et création du nouveau
        Process.cancel_timer(state.current_timer_ref)
        new_timer_ref = start_algorithm_timer(get_current_algorithm_name(state), new_timeout)
        {:noreply, %{state | current_timer_ref: new_timer_ref}}
      else
        # Timeout déjà dépassé, force le passage à l'algorithme suivant
        new_state = terminate_current_and_advance(state, :timeout_adjustment)
        {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Fonctions privées

  defp validate_planning_state(planning_state) do
    case SharedPlanningState.validate(planning_state) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp initialize_algorithm_stats do
    @default_algorithm_cycle
    |> Enum.map(fn algo_name ->
      {algo_name, %{
        executions: 0,
        total_time_ms: 0,
        avg_time_ms: 0.0,
        best_score: nil,
        worst_score: nil,
        last_improvement: nil,
        errors: 0
      }}
    end)
    |> Map.new()
  end

  defp start_current_algorithm(state) do
    algorithm_name = get_current_algorithm_name(state)
    time_budget = get_algorithm_time_budget(algorithm_name)

    case start_algorithm_process(algorithm_name, state.shared_state, time_budget) do
      {:ok, algorithm_pid} ->
        # Démarrage du timer de timeout
        timer_ref = start_algorithm_timer(algorithm_name, time_budget)

        new_state = %{state |
          current_algorithm_pid: algorithm_pid,
          current_timer_ref: timer_ref
        }

        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_algorithm_process(algorithm_name, shared_state, time_budget) do
    case algorithm_name do
      :simulated_annealing ->
        SimulatedAnnealing.start_optimization(shared_state, time_budget, self())

      :vns ->
        start_vns_process(shared_state, time_budget)

      :hybrid ->
        start_hybrid_process(shared_state, time_budget)

      _ ->
        {:error, :unknown_algorithm}
    end
  end

  # Fonctions temporaires pour VNS et Hybrid (en attendant leur implémentation)
  defp start_vns_process(shared_state, time_budget) do
    parent_pid = self()

    pid = spawn_link(fn ->
      Process.sleep(time_budget)

      improved_state = %{shared_state |
        current_score: shared_state.current_score * 0.97,  # 3% d'amélioration
        version: shared_state.version + 1,
        last_modified: DateTime.utc_now()
      }

      statistics = %{
        execution_time_ms: time_budget,
        iterations: 50,
        improvements: 3,
        final_score: improved_state.current_score
      }

      send(parent_pid, {:algorithm_complete, :vns, improved_state, statistics})
    end)

    {:ok, pid}
  end

  defp start_hybrid_process(shared_state, time_budget) do
    parent_pid = self()

    pid = spawn_link(fn ->
      Process.sleep(time_budget)

      improved_state = %{shared_state |
        current_score: shared_state.current_score * 0.93,  # 7% d'amélioration
        version: shared_state.version + 1,
        last_modified: DateTime.utc_now()
      }

      statistics = %{
        execution_time_ms: time_budget,
        iterations: 75,
        improvements: 8,
        final_score: improved_state.current_score
      }

      send(parent_pid, {:algorithm_complete, :hybrid, improved_state, statistics})
    end)

    {:ok, pid}
  end

  defp start_algorithm_timer(algorithm_name, timeout_ms) do
    Process.send_after(self(), {:algorithm_timeout, algorithm_name}, timeout_ms)
  end

  defp stop_current_algorithm(state, reason) do
    # Arrêt gracieux de l'algorithme en cours
    if state.current_algorithm_pid do
      send(state.current_algorithm_pid, {:terminate_gracefully, reason})

      # Attendre un délai raisonnable pour l'arrêt gracieux
      receive do
        {:algorithm_complete, _, final_state, stats} ->
          record_algorithm_completion(state, get_current_algorithm_name(state), final_state, stats)
      after
        2000 ->  # 2 secondes max pour l'arrêt gracieux (réduit pour les simulations)
          # Force kill si nécessaire
          if Process.alive?(state.current_algorithm_pid) do
            Process.exit(state.current_algorithm_pid, :kill)
          end
          state
      end
    else
      state
    end
    |> cleanup_current_algorithm()
  end

  defp pause_current_algorithm(state) do
    if state.current_algorithm_pid do
      send(state.current_algorithm_pid, :pause)
    end

    # Pause du timer
    if state.current_timer_ref do
      Process.cancel_timer(state.current_timer_ref)
    end

    %{state | current_timer_ref: nil}
  end

  defp resume_current_algorithm(state) do
    if state.current_algorithm_pid do
      send(state.current_algorithm_pid, :resume)
    end

    # Redémarrage du timer avec le temps restant
    algorithm_name = get_current_algorithm_name(state)
    remaining_time = calculate_remaining_time(algorithm_name)
    timer_ref = start_algorithm_timer(algorithm_name, remaining_time)

    %{state | current_timer_ref: timer_ref}
  end

  defp terminate_current_and_advance(state, reason) do
    # Arrêt de l'algorithme en cours
    updated_state = stop_current_algorithm(state, reason)

    # Passage à l'algorithme suivant
    advance_to_next_algorithm(updated_state)
  end

  defp advance_to_next_algorithm(state) do
    # Nettoyage de l'algorithme précédent
    cleaned_state = cleanup_current_algorithm(state)

    # Calcul de l'index suivant
    next_index = rem(cleaned_state.current_algorithm_index + 1, length(cleaned_state.algorithm_cycle))

    # Détermination du numéro de cycle
    new_cycle_number = if next_index == 0 do
      cleaned_state.cycle_number + 1
    else
      cleaned_state.cycle_number
    end

    # Préparation du nouvel état
    next_state = %{cleaned_state |
      current_algorithm_index: next_index,
      cycle_number: new_cycle_number
    }

    # Démarrage de l'algorithme suivant
    case start_current_algorithm(next_state) do
      {:ok, new_state} ->
        algorithm_name = get_current_algorithm_name(new_state)
        Logger.info("Advanced to algorithm: #{algorithm_name} (Cycle ##{new_state.cycle_number})")
        new_state

      {:error, reason} ->
        Logger.error("Failed to start next algorithm: #{inspect(reason)}")
        %{next_state |
          coordinator_status: :idle,
          emergency_stop_reason: {:startup_failure, reason}
        }
    end
  end

  defp cleanup_current_algorithm(state) do
    # Annulation du timer en cours
    if state.current_timer_ref do
      Process.cancel_timer(state.current_timer_ref)
    end

    %{state |
      current_algorithm_pid: nil,
      current_timer_ref: nil
    }
  end

  defp record_algorithm_completion(state, algorithm_name, final_state, statistics) do
    # Mise à jour de l'état partagé
    updated_shared_state = %{state | shared_state: final_state}

    # Mise à jour des statistiques de l'algorithme
    current_stats = Map.get(state.algorithm_statistics, algorithm_name, %{})
    updated_stats = update_algorithm_stats(current_stats, statistics, :success)

    updated_algorithm_stats = Map.put(state.algorithm_statistics, algorithm_name, updated_stats)

    # Ajout à l'historique de performance
    performance_entry = %{
      timestamp: DateTime.utc_now(),
      algorithm: algorithm_name,
      cycle: state.cycle_number,
      final_score: final_state.current_score,
      statistics: statistics,
      status: :completed
    }

    updated_performance_history = [performance_entry | state.performance_history]

    %{updated_shared_state |
      algorithm_statistics: updated_algorithm_stats,
      performance_history: updated_performance_history
    }
  end

  defp record_algorithm_error(state, algorithm_name, error_reason) do
    # Mise à jour des statistiques d'erreur
    current_stats = Map.get(state.algorithm_statistics, algorithm_name, %{})
    updated_stats = %{current_stats | errors: (current_stats.errors || 0) + 1}

    updated_algorithm_stats = Map.put(state.algorithm_statistics, algorithm_name, updated_stats)

    # Ajout à l'historique de performance
    performance_entry = %{
      timestamp: DateTime.utc_now(),
      algorithm: algorithm_name,
      cycle: state.cycle_number,
      error_reason: error_reason,
      status: :error
    }

    updated_performance_history = [performance_entry | state.performance_history]

    %{state |
      algorithm_statistics: updated_algorithm_stats,
      performance_history: updated_performance_history
    }
  end

  defp should_continue_after_error(error_reason) do
    # Politique de continuation après erreur
    case error_reason do
      :timeout -> true
      :memory_error -> false
      :invalid_state -> false
      _ -> true  # Par défaut, continuer
    end
  end

  defp update_algorithm_stats(current_stats, new_statistics, result_type) do
    executions = (current_stats.executions || 0) + 1
    total_time = (current_stats.total_time_ms || 0) + (new_statistics.execution_time_ms || 0)
    avg_time = total_time / executions

    updated_stats = %{current_stats |
      executions: executions,
      total_time_ms: total_time,
      avg_time_ms: avg_time
    }

    case result_type do
      :success ->
        final_score = new_statistics.final_score

        %{updated_stats |
          best_score: min_score(current_stats.best_score, final_score),
          worst_score: max_score(current_stats.worst_score, final_score),
          last_improvement: if(new_statistics.improvements > 0, do: DateTime.utc_now(), else: current_stats.last_improvement)
        }

      :error ->
        updated_stats
    end
  end

  defp min_score(nil, score), do: score
  defp min_score(current, score), do: min(current, score)

  defp max_score(nil, score), do: score
  defp max_score(current, score), do: max(current, score)

  defp get_current_algorithm_name(state) do
    Enum.at(state.algorithm_cycle, state.current_algorithm_index)
  end

  defp get_algorithm_time_budget(algorithm_name) do
    case algorithm_name do
      :simulated_annealing -> ParameterManager.get("optimizer", "simulated_annealing_timeout") || 30_000
      :vns -> ParameterManager.get("optimizer", "vns_timeout") || 30_000
      :hybrid -> ParameterManager.get("optimizer", "hybrid_timeout") || 30_000
      _ -> ParameterManager.get("optimizer", "algorithm_time_budget") || 30_000
    end
  end

  defp calculate_adjusted_timeout(new_budget_ms) do
    # Pour simplifier, retourner le nouveau budget complet
    # Une implémentation plus sophistiquée calculerait le temps déjà écoulé
    new_budget_ms
  end

  defp calculate_remaining_time(algorithm_name) do
    # Pour simplifier, retourner le budget complet
    # Une implémentation plus sophistiquée suivrait le temps écoulé
    get_algorithm_time_budget(algorithm_name)
  end

  defp send_to_current_algorithm(state, message) do
    if state.current_algorithm_pid and Process.alive?(state.current_algorithm_pid) do
      send(state.current_algorithm_pid, message)
    end
  end

  defp get_current_score(state) do
    case state.shared_state do
      nil -> nil
      shared_state -> shared_state.current_score
    end
  end

  defp get_shared_state_info(nil), do: %{status: :no_state}
  defp get_shared_state_info(shared_state) do
    %{
      status: :available,
      current_score: shared_state.current_score,
      version: shared_state.version,
      order_count: length(shared_state.order_index),
      task_count: map_size(shared_state.task_assignments),
      immutable_tasks: MapSet.size(shared_state.immutable_tasks),
      last_modified: shared_state.last_modified
    }
  end

  defp get_memory_usage do
    {:memory, memory_info} = :erlang.process_info(self(), :memory)
    memory_info
  end

  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms / 1000
  end
end
