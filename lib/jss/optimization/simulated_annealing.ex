defmodule JSS.Optimization.SimulatedAnnealing do
  @moduledoc """
  Implémentation de l'algorithme de recuit simulé pour l'optimisation des swaps d'ordres.
  Accepte les dégradations selon une probabilité décroissante avec la température.
  """

  use GenServer
  require Logger

  alias JSS.Core.SharedPlanningState
  alias JSS.Optimization.CostCalculator
  alias JSS.Actors.SwapEvaluator
  alias JSS.System.ParameterManager

  @type temperature :: float()
  @type cooling_rate :: float()
  @type move_type :: :swap_orders | :reassign_task

  defstruct [
    :shared_state,
    :coordinator_pid,
    :current_temperature,
    :min_temperature,
    :cooling_rate,
    :time_budget_ms,
    :start_time,
    :iteration_count,
    :accepted_moves,
    :rejected_moves,
    :improvements,
    :status,
    :best_state,
    :best_score,
    :move_probabilities
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Démarre l'optimisation par recuit simulé.
  """
  def start_optimization(shared_state, time_budget_ms, coordinator_pid) do
    GenServer.start_link(__MODULE__, {shared_state, time_budget_ms, coordinator_pid})
  end

  # Callbacks GenServer

  @impl true
  def init({shared_state, time_budget_ms, coordinator_pid}) do
    # Chargement des paramètres
    initial_temperature = ParameterManager.get("optimizer", "sa_initial_temperature")
    cooling_rate = ParameterManager.get("optimizer", "sa_cooling_rate")
    min_temperature = ParameterManager.get("optimizer", "sa_min_temperature")
    swap_probability = ParameterManager.get("optimizer", "sa_swap_probability")
    reassignment_probability = ParameterManager.get("optimizer", "sa_reassignment_probability")

    # État initial
    initial_state = %__MODULE__{
      shared_state: shared_state,
      coordinator_pid: coordinator_pid,
      current_temperature: initial_temperature,
      min_temperature: min_temperature,
      cooling_rate: cooling_rate,
      time_budget_ms: time_budget_ms,
      start_time: System.monotonic_time(:millisecond),
      iteration_count: 0,
      accepted_moves: 0,
      rejected_moves: 0,
      improvements: 0,
      status: :running,
      best_state: shared_state,
      best_score: shared_state.current_score,
      move_probabilities: %{
        swap_orders: swap_probability,
        reassign_task: reassignment_probability
      }
    }

    # Démarrage de la boucle d'optimisation
    send(self(), :optimize_step)

    Logger.info("SimulatedAnnealing started - Temperature: #{initial_temperature}, Budget: #{time_budget_ms}ms")

    {:ok, initial_state}
  end

  @impl true
  def handle_info(:optimize_step, state) do
    case should_continue?(state) do
      true ->
        # Une itération d'optimisation
        new_state = perform_optimization_step(state)

        # Programmation de la prochaine itération
        send(self(), :optimize_step)

        {:noreply, new_state}

      false ->
        # Fin de l'optimisation
        final_state = finalize_optimization(state)
        notify_completion(final_state)
        {:stop, :normal, final_state}
    end
  end

  @impl true
  def handle_info({:terminate_gracefully, reason}, state) do
    Logger.info("SimulatedAnnealing terminating gracefully: #{reason}")
    final_state = finalize_optimization(state)
    notify_completion(final_state)
    {:stop, :normal, final_state}
  end

  @impl true
  def handle_info(:pause, state) do
    Logger.info("SimulatedAnnealing paused")
    {:noreply, %{state | status: :paused}}
  end

  @impl true
  def handle_info(:resume, state) do
    Logger.info("SimulatedAnnealing resumed")
    send(self(), :optimize_step)
    {:noreply, %{state | status: :running}}
  end

  @impl true
  def handle_info({:planning_state_updated, new_planning_state, reason}, state) do
    Logger.debug("Planning state updated during SA optimization: #{reason}")
    updated_state = %{state | shared_state: new_planning_state}
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Fonctions privées - Logique d'optimisation

  defp should_continue?(state) do
    # Vérification du statut
    if state.status != :running, do: false

    # Vérification du temps
    current_time = System.monotonic_time(:millisecond)
    elapsed_time = current_time - state.start_time
    if elapsed_time >= state.time_budget_ms, do: false

    # Vérification de la température minimale
    if state.current_temperature <= state.min_temperature, do: false

    # Continue sinon
    true
  end

  defp perform_optimization_step(state) do
    # 1. Choisir un type de mouvement
    move_type = choose_move_type(state.move_probabilities)

    # 2. Générer un mouvement
    case generate_move(state, move_type) do
      {:ok, move} ->
        # 3. Évaluer le mouvement
        case evaluate_move(state, move) do
          {:ok, delta_score, new_planning_state} ->
            # 4. Décider d'accepter ou rejeter
            if accept_move?(delta_score, state.current_temperature) do
              accept_move(state, move, delta_score, new_planning_state)
            else
              reject_move(state, move, delta_score)
            end

          {:error, reason} ->
            Logger.debug("Move evaluation failed: #{inspect(reason)}")
            update_iteration_stats(state)
        end

      {:error, reason} ->
        Logger.debug("Move generation failed: #{inspect(reason)}")
        update_iteration_stats(state)
    end
  end

  defp choose_move_type(probabilities) do
    random_value = :rand.uniform()

    cond do
      random_value <= probabilities.swap_orders -> :swap_orders
      true -> :reassign_task
    end
  end

  defp generate_move(state, :swap_orders) do
    order_ids = state.shared_state.order_index

    if length(order_ids) < 2 do
      {:error, :insufficient_orders}
    else
      # Sélection pondérée privilégiant les ordres critiques
      {order_a_id, order_b_id} = select_weighted_order_pair(state, order_ids)
      {:ok, {:swap_orders, order_a_id, order_b_id}}
    end
  end

  defp generate_move(state, :reassign_task) do
    task_assignments = state.shared_state.task_assignments

    if map_size(task_assignments) == 0 do
      {:error, :no_task_assignments}
    else
      # Sélection d'une tâche à réassigner
      {task_id, current_machine_id} = Enum.random(task_assignments)

      # Recherche d'une machine alternative
      task = state.shared_state.tasks[task_id]
      compatible_machines = find_compatible_machines(state, task)
      alternative_machines = List.delete(compatible_machines, current_machine_id)

      if Enum.empty?(alternative_machines) do
        {:error, :no_alternative_machines}
      else
        new_machine_id = Enum.random(alternative_machines)
        {:ok, {:reassign_task, task_id, new_machine_id}}
      end
    end
  end

  defp select_weighted_order_pair(state, order_ids) do
    # Privilégier les ordres avec des tâches sur le chemin critique
    critical_task_visit_multiplier = ParameterManager.get("optimizer", "critical_task_visit_multiplier")

    weights =
      order_ids
      |> Enum.map(fn order_id ->
        order = state.shared_state.orders[order_id]
        has_critical_tasks = Enum.any?(order.task_ids, fn task_id ->
          task_id in state.shared_state.critical_path_tasks
        end)

        weight = if has_critical_tasks, do: critical_task_visit_multiplier, else: 1.0
        {order_id, weight}
      end)

    # Sélection pondérée de deux ordres différents
    order_a_id = weighted_random_selection(weights)
    remaining_weights = List.keydelete(weights, order_a_id, 0)
    order_b_id = weighted_random_selection(remaining_weights)

    {order_a_id, order_b_id}
  end

  defp weighted_random_selection(weights) do
    total_weight = Enum.reduce(weights, 0.0, fn {_, weight}, acc -> acc + weight end)
    random_value = :rand.uniform() * total_weight

    {selected, _} = Enum.reduce_while(weights, {nil, 0.0}, fn {item, weight}, {_, acc} ->
      new_acc = acc + weight
      if random_value <= new_acc do
        {:halt, {item, new_acc}}
      else
        {:cont, {item, new_acc}}
      end
    end)

    selected
  end

  defp find_compatible_machines(state, task) do
    state.shared_state.machines
    |> Enum.filter(fn {_machine_id, machine} ->
      JSS.Core.Task.compatible_with_machine_type?(task, machine.machine_type)
    end)
    |> Enum.map(fn {machine_id, _machine} -> machine_id end)
  end

  defp evaluate_move(state, {:swap_orders, order_a_id, order_b_id}) do
    case CostCalculator.calculate_swap_impact(state.shared_state, order_a_id, order_b_id) do
      {:ok, delta_score, breakdown} ->
        # Simulation de l'application du swap pour obtenir le nouvel état
        case SharedPlanningState.swap_orders(state.shared_state, order_a_id, order_b_id) do
          {:error, reason} -> {:error, reason}
          new_state -> {:ok, delta_score, new_state}
        end

      {:error, reason} -> {:error, reason}
    end
  end

  defp evaluate_move(state, {:reassign_task, task_id, new_machine_id}) do
    case CostCalculator.calculate_reassignment_impact(state.shared_state, task_id, new_machine_id) do
      {:ok, delta_score, breakdown} ->
        # Simulation de l'application de la réassignation
        case SharedPlanningState.reassign_task(state.shared_state, task_id, new_machine_id) do
          {:error, reason} -> {:error, reason}
          new_state -> {:ok, delta_score, new_state}
        end

      {:error, reason} -> {:error, reason}
    end
  end

  defp accept_move?(delta_score, temperature) do
    cond do
      delta_score <= 0 -> true  # Amélioration, toujours accepter
      temperature <= 0 -> false  # Température nulle, rejeter les dégradations
      true ->
        # Probabilité d'acceptation selon la formule de Boltzmann
        probability = :math.exp(-delta_score / temperature)
        :rand.uniform() < probability
    end
  end

  defp accept_move(state, move, delta_score, new_planning_state) do
    # Mise à jour de l'état de planification
    updated_state = %{state | shared_state: new_planning_state}

    # Mise à jour du meilleur état si amélioration
    {final_state, improvement_count} = if new_planning_state.current_score < state.best_score do
      Logger.debug("New best score found: #{new_planning_state.current_score} (improvement: #{abs(delta_score)})")
      {
        %{updated_state |
          best_state: new_planning_state,
          best_score: new_planning_state.current_score
        },
        state.improvements + 1
      }
    else
      {updated_state, state.improvements}
    end

    # Refroidissement et mise à jour des statistiques
    final_state
    |> cool_temperature()
    |> update_iteration_stats()
    |> Map.merge(%{
      accepted_moves: state.accepted_moves + 1,
      improvements: improvement_count
    })
  end

  defp reject_move(state, move, delta_score) do
    # Seulement refroidissement et mise à jour des statistiques
    state
    |> cool_temperature()
    |> update_iteration_stats()
    |> Map.merge(%{
      rejected_moves: state.rejected_moves + 1
    })
  end

  defp cool_temperature(state) do
    new_temperature = state.current_temperature * state.cooling_rate
    clamped_temperature = max(new_temperature, state.min_temperature)

    %{state | current_temperature: clamped_temperature}
  end

  defp update_iteration_stats(state) do
    %{state | iteration_count: state.iteration_count + 1}
  end

  defp finalize_optimization(state) do
    # Utiliser le meilleur état trouvé
    final_shared_state = %{state.best_state |
      last_modified: DateTime.utc_now(),
      version: state.best_state.version + 1
    }

    %{state |
      shared_state: final_shared_state,
      status: :completed
    }
  end

  defp notify_completion(state) do
    execution_time = System.monotonic_time(:millisecond) - state.start_time

    statistics = %{
      execution_time_ms: execution_time,
      iterations: state.iteration_count,
      accepted_moves: state.accepted_moves,
      rejected_moves: state.rejected_moves,
      improvements: state.improvements,
      final_score: state.best_score,
      final_temperature: state.current_temperature,
      acceptance_ratio: calculate_acceptance_ratio(state)
    }

    Logger.info("SimulatedAnnealing completed - Iterations: #{state.iteration_count}, " <>
                "Score: #{state.best_score}, Acceptance: #{Float.round(statistics.acceptance_ratio * 100, 1)}%")

    send(state.coordinator_pid, {:algorithm_complete, :simulated_annealing, state.shared_state, statistics})
  end

  defp calculate_acceptance_ratio(state) do
    total_moves = state.accepted_moves + state.rejected_moves
    if total_moves > 0 do
      state.accepted_moves / total_moves
    else
      0.0
    end
  end

  @doc """
  Diagnostic des performances en temps réel.
  """
  def get_real_time_stats(pid) do
    GenServer.call(pid, :get_real_time_stats)
  end

  @impl true
  def handle_call(:get_real_time_stats, _from, state) do
    elapsed_time = System.monotonic_time(:millisecond) - state.start_time

    stats = %{
      status: state.status,
      elapsed_time_ms: elapsed_time,
      remaining_time_ms: max(0, state.time_budget_ms - elapsed_time),
      current_temperature: state.current_temperature,
      iteration_count: state.iteration_count,
      current_score: state.shared_state.current_score,
      best_score: state.best_score,
      accepted_moves: state.accepted_moves,
      rejected_moves: state.rejected_moves,
      acceptance_ratio: calculate_acceptance_ratio(state),
      improvements: state.improvements,
      iterations_per_second: if(elapsed_time > 0, do: state.iteration_count / (elapsed_time / 1000), else: 0)
    }

    {:reply, stats, state}
  end

  @doc """
  Ajuste les paramètres en cours d'exécution.
  """
  def adjust_parameters(pid, new_params) do
    GenServer.cast(pid, {:adjust_parameters, new_params})
  end

  @impl true
  def handle_cast({:adjust_parameters, new_params}, state) do
    updated_state = Enum.reduce(new_params, state, fn {param, value}, acc ->
      case param do
        :cooling_rate -> %{acc | cooling_rate: value}
        :min_temperature -> %{acc | min_temperature: value}
        :move_probabilities -> %{acc | move_probabilities: Map.merge(acc.move_probabilities, value)}
        _ -> acc
      end
    end)

    Logger.info("SimulatedAnnealing parameters adjusted: #{inspect(new_params)}")
    {:noreply, updated_state}
  end
end
