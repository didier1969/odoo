defmodule JSS.Optimization.CostCalculator do
  @moduledoc """
  Calculateur de la fonction de coût multi-objectifs pour l'optimisation.
  Implémente la formule : Score = (Delays × delay_weight) + (Advances × advance_weight) +
                                 (Setup_Times × setup_weight) + (Pool_Overcost) + (Hierarchy_Overcost)
  """

  alias JSS.Core.{SharedPlanningState, Task, Machine, Order, Pool, Article}
  alias JSS.System.ParameterManager

  require Logger

  @type cost_breakdown :: %{
    delays: float(),
    advances: float(),
    setup_times: float(),
    pool_overcost: float(),
    hierarchy_overcost: float()
  }

  @doc """
  Calcule le score global et sa décomposition pour un état de planification.
  """
  def calculate_full_score(%SharedPlanningState{} = state) do
    # Récupération des poids depuis les paramètres
    delay_weight = ParameterManager.get("optimizer", "delay_weight")
    advance_weight = ParameterManager.get("optimizer", "advance_weight")
    setup_weight = ParameterManager.get("optimizer", "setup_weight")

    # Calcul de chaque composante
    delays_cost = calculate_delays_cost(state, delay_weight)
    advances_cost = calculate_advances_cost(state, advance_weight)
    setup_times_cost = calculate_setup_times_cost(state, setup_weight)
    pool_overcost = calculate_pool_overcost(state)
    hierarchy_overcost = calculate_hierarchy_overcost(state)

    %{
      delays: delays_cost,
      advances: advances_cost,
      setup_times: setup_times_cost,
      pool_overcost: pool_overcost,
      hierarchy_overcost: hierarchy_overcost
    }
  end

  @doc """
  Calcule seulement le score total sans décomposition (optimisé pour performance).
  """
  def calculate_total_score(%SharedPlanningState{} = state) do
    breakdown = calculate_full_score(state)
    Map.values(breakdown) |> Enum.sum()
  end

  @doc """
  Calcule l'impact d'un swap de commandes sur le score.
  Retourne {delta_score, detailed_breakdown}.
  """
  def calculate_swap_impact(state, order_a_id, order_b_id) do
    # Score actuel
    current_breakdown = calculate_full_score(state)
    current_score = Map.values(current_breakdown) |> Enum.sum()

    # Simulation du swap
    case SharedPlanningState.swap_orders(state, order_a_id, order_b_id) do
      {:error, reason} ->
        {:error, reason}

      new_state ->
        new_breakdown = calculate_full_score(new_state)
        new_score = Map.values(new_breakdown) |> Enum.sum()

        delta_breakdown = %{
          delays: new_breakdown.delays - current_breakdown.delays,
          advances: new_breakdown.advances - current_breakdown.advances,
          setup_times: new_breakdown.setup_times - current_breakdown.setup_times,
          pool_overcost: new_breakdown.pool_overcost - current_breakdown.pool_overcost,
          hierarchy_overcost: new_breakdown.hierarchy_overcost - current_breakdown.hierarchy_overcost
        }

        delta_score = new_score - current_score

        {:ok, delta_score, delta_breakdown}
    end
  end

  @doc """
  Calcule l'impact d'une réassignation de tâche sur le score.
  """
  def calculate_reassignment_impact(state, task_id, new_machine_id) do
    current_breakdown = calculate_full_score(state)
    current_score = Map.values(current_breakdown) |> Enum.sum()

    case SharedPlanningState.reassign_task(state, task_id, new_machine_id) do
      {:error, reason} ->
        {:error, reason}

      new_state ->
        new_breakdown = calculate_full_score(new_state)
        new_score = Map.values(new_breakdown) |> Enum.sum()

        delta_score = new_score - current_score
        {:ok, delta_score, new_breakdown}
    end
  end

  # Calcul des retards
  defp calculate_delays_cost(state, delay_weight) do
    state.task_assignments
    |> Enum.reduce(0.0, fn {task_id, machine_id}, acc ->
      task = state.tasks[task_id]
      order = state.orders[task.order_id]

      case calculate_task_delay(state, task, order) do
        delay_seconds when delay_seconds > 0 ->
          acc + (delay_seconds * delay_weight)
        _ ->
          acc
      end
    end)
  end

  # Calcul des avances
  defp calculate_advances_cost(state, advance_weight) do
    state.task_assignments
    |> Enum.reduce(0.0, fn {task_id, machine_id}, acc ->
      task = state.tasks[task_id]
      order = state.orders[task.order_id]

      case calculate_task_delay(state, task, order) do
        delay_seconds when delay_seconds < 0 ->
          # Avance = délai négatif
          advance_seconds = abs(delay_seconds)
          acc + (advance_seconds * advance_weight)
        _ ->
          acc
      end
    end)
  end

  # Calcul des temps de changement d'outils
  defp calculate_setup_times_cost(state, setup_weight) do
    # Grouper les tâches par machine pour calculer les changements
    tasks_by_machine =
      state.task_assignments
      |> Enum.group_by(fn {_task_id, machine_id} -> machine_id end, fn {task_id, _} -> task_id end)

    tasks_by_machine
    |> Enum.reduce(0.0, fn {machine_id, task_ids}, acc ->
      machine = state.machines[machine_id]
      setup_cost = calculate_machine_setup_cost(state, machine, task_ids)
      acc + (setup_cost * setup_weight)
    end)
  end

  # Calcul du surcoût de spillover entre pools
  defp calculate_pool_overcost(state) do
    state.task_assignments
    |> Enum.reduce(0.0, fn {task_id, machine_id}, acc ->
      task = state.tasks[task_id]
      machine = state.machines[machine_id]
      article = state.articles[task.article_id]

      optimal_pool = state.pools[article.optimal_pool_id]
      machine_pool = state.pools[machine.pool_id]

      if optimal_pool.pool_id != machine_pool.pool_id do
        # Calcul du surcoût de spillover
        task_duration_hours = Task.get_duration_seconds(task) / 3600.0
        rate_difference = machine_pool.technology_rates[machine.machine_type] -
                         optimal_pool.technology_rates[machine.machine_type]
        spillover_cost = task_duration_hours * max(0.0, rate_difference)
        acc + spillover_cost
      else
        acc
      end
    end)
  end

  # Calcul du surcoût hiérarchique (machine supérieure)
  defp calculate_hierarchy_overcost(state) do
    hierarchy_flat_rate = ParameterManager.get("optimizer", "hierarchy_flat_rate")

    state.task_assignments
    |> Enum.reduce(0.0, fn {task_id, machine_id}, acc ->
      task = state.tasks[task_id]
      machine = state.machines[machine_id]
      article = state.articles[task.article_id]

      if is_superior_machine?(machine, article) do
        acc + hierarchy_flat_rate
      else
        acc
      end
    end)
  end

  # Calcule le retard/avance d'une tâche par rapport à sa date cible
  defp calculate_task_delay(state, task, order) do
    case Map.get(state.task_start_times, task.task_id) do
      nil -> 0  # Pas encore planifiée
      planned_end ->
        target_date = order.requested_delivery_date
        DateTime.diff(planned_end, target_date, :second)
    end
  end

  # Calcule le coût de changement d'outils pour une machine
  defp calculate_machine_setup_cost(state, machine, task_ids) do
    # Trier les tâches selon l'ordre d'index des commandes
    sorted_tasks =
      task_ids
      |> Enum.map(fn task_id ->
        task = state.tasks[task_id]
        order = state.orders[task.order_id]
        {task, order.index_position}
      end)
      |> Enum.sort_by(fn {_task, index_position} -> index_position end)
      |> Enum.map(fn {task, _} -> task end)

    # Calculer les changements d'outils séquentiels
    sorted_tasks
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [prev_task, next_task], acc ->
      prev_article = state.articles[prev_task.article_id]
      next_article = state.articles[next_task.article_id]

      setup_time_seconds = Machine.get_setup_time(machine,
        prev_article.article_id,
        next_article.article_id
      )

      setup_cost = Machine.calculate_setup_cost(machine,
        prev_article.article_id,
        next_article.article_id
      )

      acc + setup_cost
    end)
  end

  # Vérifie si une machine est de niveau supérieur pour un article
  defp is_superior_machine?(machine, article) do
    # Logique à définir : par exemple, si le type de machine est dans une hiérarchie
    # Pour simplifier, on considère qu'une machine est supérieure si son taux horaire
    # est significativement plus élevé que la moyenne pour ce type d'article

    avg_rate = ParameterManager.get("demo", "demo_technology_rate_min") +
              (ParameterManager.get("demo", "demo_technology_rate_max") -
               ParameterManager.get("demo", "demo_technology_rate_min")) / 2

    machine.technology_rate_chf_per_hour > avg_rate * 1.2
  end

  @doc """
  Calcule les métriques de performance détaillées.
  """
  def calculate_performance_metrics(state) do
    total_tasks = map_size(state.task_assignments)

    if total_tasks == 0 do
      %{
        total_tasks: 0,
        avg_delay_hours: 0.0,
        max_delay_hours: 0.0,
        on_time_delivery_percent: 100.0,
        machine_utilization_percent: 0.0,
        setup_time_percent: 0.0
      }
    else
      delays = calculate_all_task_delays(state)

      %{
        total_tasks: total_tasks,
        avg_delay_hours: Enum.sum(delays) / (length(delays) * 3600.0),
        max_delay_hours: Enum.max(delays, fn -> 0 end) / 3600.0,
        on_time_delivery_percent: calculate_on_time_delivery_percent(delays),
        machine_utilization_percent: calculate_avg_machine_utilization(state),
        setup_time_percent: calculate_setup_time_percentage(state)
      }
    end
  end

  # Calcule tous les délais de tâches
  defp calculate_all_task_delays(state) do
    state.task_assignments
    |> Enum.map(fn {task_id, _machine_id} ->
      task = state.tasks[task_id]
      order = state.orders[task.order_id]
      calculate_task_delay(state, task, order)
    end)
  end

  # Calcule le pourcentage de livraisons à temps
  defp calculate_on_time_delivery_percent(delays) do
    if Enum.empty?(delays) do
      100.0
    else
      on_time_count = Enum.count(delays, fn delay -> delay <= 0 end)
      (on_time_count / length(delays)) * 100.0
    end
  end

  # Calcule l'utilisation moyenne des machines
  defp calculate_avg_machine_utilization(state) do
    if map_size(state.machine_loads) == 0 do
      0.0
    else
      total_load = Map.values(state.machine_loads) |> Enum.sum()
      total_load / map_size(state.machine_loads)
    end
  end

  # Calcule le pourcentage de temps consacré aux changements d'outils
  defp calculate_setup_time_percentage(state) do
    # Calcul simplifié : ratio temps de setup / temps total de production
    total_production_time = calculate_total_production_time(state)
    total_setup_time = calculate_total_setup_time(state)

    if total_production_time > 0 do
      (total_setup_time / (total_production_time + total_setup_time)) * 100.0
    else
      0.0
    end
  end

  defp calculate_total_production_time(state) do
    state.task_assignments
    |> Enum.reduce(0, fn {task_id, _machine_id}, acc ->
      task = state.tasks[task_id]
      acc + Task.get_duration_seconds(task)
    end)
  end

  defp calculate_total_setup_time(state) do
    state.machines
    |> Enum.reduce(0, fn {machine_id, machine}, acc ->
      task_ids = get_machine_task_ids(state, machine_id)
      setup_time = calculate_machine_total_setup_time(state, machine, task_ids)
      acc + setup_time
    end)
  end

  defp get_machine_task_ids(state, machine_id) do
    state.task_assignments
    |> Enum.filter(fn {_task_id, assigned_machine_id} ->
      assigned_machine_id == machine_id
    end)
    |> Enum.map(fn {task_id, _} -> task_id end)
  end

  defp calculate_machine_total_setup_time(state, machine, task_ids) do
    sorted_tasks =
      task_ids
      |> Enum.map(fn task_id ->
        task = state.tasks[task_id]
        order = state.orders[task.order_id]
        {task, order.index_position}
      end)
      |> Enum.sort_by(fn {_task, index_position} -> index_position end)
      |> Enum.map(fn {task, _} -> task end)

    sorted_tasks
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [prev_task, next_task], acc ->
      prev_article = state.articles[prev_task.article_id]
      next_article = state.articles[next_task.article_id]

      setup_time = Machine.get_setup_time(machine,
        prev_article.article_id,
        next_article.article_id
      )

      acc + setup_time
    end)
  end

  @doc """
  Valide la cohérence des calculs de coût.
  """
  def validate_cost_calculation(state) do
    try do
      breakdown = calculate_full_score(state)

      # Vérifications de base
      errors = []

      errors = if breakdown.delays < 0,
        do: ["delays cost cannot be negative" | errors], else: errors

      errors = if breakdown.advances < 0,
        do: ["advances cost cannot be negative" | errors], else: errors

      errors = if breakdown.setup_times < 0,
        do: ["setup_times cost cannot be negative" | errors], else: errors

      # Vérification de cohérence des assignations
      errors = if map_size(state.task_assignments) > map_size(state.tasks),
        do: ["more assignments than tasks" | errors], else: errors

      case errors do
        [] -> {:ok, breakdown}
        errors -> {:error, errors}
      end
    rescue
      error ->
        Logger.error("Cost calculation failed: #{inspect(error)}")
        {:error, :calculation_failed}
    end
  end
end
