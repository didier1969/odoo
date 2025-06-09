defmodule JSS.Core.SharedPlanningState do
  @moduledoc """
  État global de la planification partagé entre tous les algorithmes d'optimisation.
  Structure immutable avec fonctions de mise à jour et validation.
  """

  alias JSS.Core.{Order, Task, Machine, Pool, Article}

  @type order_id :: String.t()
  @type task_id :: String.t()
  @type machine_id :: String.t()
  @type pool_id :: String.t()
  @type article_id :: String.t()

  @type score_breakdown :: %{
    delays: float(),
    advances: float(),
    setup_times: float(),
    pool_overcost: float(),
    hierarchy_overcost: float()
  }

  @type t :: %__MODULE__{
    # État principal de la planification
    order_index: [order_id()],                           # Séquence globale des commandes
    task_assignments: %{task_id() => machine_id()},      # Assignation tâche -> machine
    current_score: float(),                              # Score global actuel

    # Métadonnées temporelles
    planning_horizon_start: DateTime.t(),                # Début de la fenêtre active
    planning_horizon_end: DateTime.t(),                  # Fin de la fenêtre active
    last_modified: DateTime.t(),                         # Dernière modification

    # Cache pour performance
    score_breakdown: score_breakdown(),                  # Détail du score
    task_start_times: %{task_id() => DateTime.t()},     # Temps de début calculés
    machine_loads: %{machine_id() => float()},          # Charge par machine (%)
    critical_path_tasks: [task_id()],                    # Tâches sur chemin critique

    # État des contraintes
    immutable_tasks: MapSet.t(task_id()),               # Tâches déjà démarrées
    blocked_tasks: MapSet.t(task_id()),                 # Tâches bloquées temporairement

    # Validation et cohérence
    consistency_hash: binary(),                          # Hash pour détecter corruptions
    version: integer(),                                  # Version incrémentale

    # Références aux données statiques (pas de duplication)
    orders: %{order_id() => Order.t()},                 # Données des commandes
    tasks: %{task_id() => Task.t()},                    # Données des tâches
    machines: %{machine_id() => Machine.t()},           # Données des machines
    pools: %{pool_id() => Pool.t()},                    # Données des pools
    articles: %{article_id() => Article.t()}            # Données des articles
  }

  defstruct [
    :order_index,
    :task_assignments,
    :current_score,
    :planning_horizon_start,
    :planning_horizon_end,
    :last_modified,
    :score_breakdown,
    :task_start_times,
    :machine_loads,
    :critical_path_tasks,
    :immutable_tasks,
    :blocked_tasks,
    :consistency_hash,
    :version,
    :orders,
    :tasks,
    :machines,
    :pools,
    :articles
  ]

  @doc """
  Crée un nouvel état de planification avec les données initiales.
  """
  def new(orders, tasks, machines, pools, articles, opts \\ []) do
    now = DateTime.utc_now()
    horizon_days = Keyword.get(opts, :horizon_days, 90)

    initial_state = %__MODULE__{
      order_index: Map.keys(orders) |> Enum.sort(),
      task_assignments: %{},
      current_score: 0.0,
      planning_horizon_start: now,
      planning_horizon_end: DateTime.add(now, horizon_days * 24 * 3600, :second),
      last_modified: now,
      score_breakdown: %{
        delays: 0.0,
        advances: 0.0,
        setup_times: 0.0,
        pool_overcost: 0.0,
        hierarchy_overcost: 0.0
      },
      task_start_times: %{},
      machine_loads: %{},
      critical_path_tasks: [],
      immutable_tasks: MapSet.new(),
      blocked_tasks: MapSet.new(),
      consistency_hash: "",
      version: 1,
      orders: orders,
      tasks: tasks,
      machines: machines,
      pools: pools,
      articles: articles
    }

    initial_state
    |> calculate_initial_assignments()
    |> recalculate_state()
  end

  @doc """
  Échange deux commandes dans l'index global.
  Recalcule automatiquement tous les impacts.
  """
  def swap_orders(state, order_a_id, order_b_id) do
    case {find_order_position(state, order_a_id), find_order_position(state, order_b_id)} do
      {{:ok, pos_a}, {:ok, pos_b}} ->
        new_index =
          state.order_index
          |> List.replace_at(pos_a, order_b_id)
          |> List.replace_at(pos_b, order_a_id)

        %{state | order_index: new_index}
        |> recalculate_state()
        |> increment_version()

      _ ->
        {:error, :orders_not_found}
    end
  end

  @doc """
  Réassigne une tâche à une nouvelle machine.
  Valide la compatibilité avant l'assignation.
  """
  def reassign_task(state, task_id, new_machine_id) do
    with {:ok, task} <- Map.fetch(state.tasks, task_id),
         {:ok, machine} <- Map.fetch(state.machines, new_machine_id),
         true <- is_compatible?(task, machine),
         false <- MapSet.member?(state.immutable_tasks, task_id) do

      new_assignments = Map.put(state.task_assignments, task_id, new_machine_id)

      %{state | task_assignments: new_assignments}
      |> recalculate_state()
      |> increment_version()
    else
      :error -> {:error, :task_or_machine_not_found}
      false -> {:error, :incompatible_assignment}
      true -> {:error, :task_immutable}
    end
  end

  @doc """
  Marque des tâches comme immutables (déjà démarrées).
  """
  def mark_tasks_immutable(state, task_ids) when is_list(task_ids) do
    new_immutable = Enum.reduce(task_ids, state.immutable_tasks, &MapSet.put(&2, &1))

    %{state | immutable_tasks: new_immutable}
    |> increment_version()
  end

  @doc """
  Bloque temporairement des tâches (machine en panne, etc.).
  """
  def block_tasks(state, task_ids, reason \\ :external_event) when is_list(task_ids) do
    new_blocked = Enum.reduce(task_ids, state.blocked_tasks, &MapSet.put(&2, &1))

    %{state | blocked_tasks: new_blocked}
    |> recalculate_state()
    |> increment_version()
  end

  @doc """
  Débloque des tâches précédemment bloquées.
  """
  def unblock_tasks(state, task_ids) when is_list(task_ids) do
    new_blocked = Enum.reduce(task_ids, state.blocked_tasks, &MapSet.delete(&2, &1))

    %{state | blocked_tasks: new_blocked}
    |> recalculate_state()
    |> increment_version()
  end

  @doc """
  Valide la cohérence de l'état complet.
  """
  def validate(state) do
    with :ok <- validate_order_index(state),
         :ok <- validate_task_assignments(state),
         :ok <- validate_temporal_constraints(state),
         :ok <- validate_consistency_hash(state) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Calcule un hash de cohérence pour détecter les corruptions.
  """
  def calculate_consistency_hash(state) do
    hash_data = %{
      order_index: state.order_index,
      task_assignments: state.task_assignments,
      immutable_tasks: MapSet.to_list(state.immutable_tasks),
      version: state.version
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(hash_data))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Met à jour le hash de cohérence.
  """
  def update_consistency_hash(state) do
    %{state | consistency_hash: calculate_consistency_hash(state)}
  end

  @doc """
  Sérialise l'état pour persistance ou transmission.
  """
  def serialize(state) do
    %{
      order_index: state.order_index,
      task_assignments: state.task_assignments,
      current_score: state.current_score,
      score_breakdown: state.score_breakdown,
      immutable_tasks: MapSet.to_list(state.immutable_tasks),
      blocked_tasks: MapSet.to_list(state.blocked_tasks),
      version: state.version,
      consistency_hash: state.consistency_hash,
      serialized_at: DateTime.utc_now()
    }
  end

  @doc """
  Désérialise un état depuis une représentation sérialisée.
  """
  def deserialize(serialized_data, orders, tasks, machines, pools, articles) do
    %__MODULE__{
      order_index: serialized_data.order_index,
      task_assignments: serialized_data.task_assignments,
      current_score: serialized_data.current_score,
      score_breakdown: serialized_data.score_breakdown,
      immutable_tasks: MapSet.new(serialized_data.immutable_tasks),
      blocked_tasks: MapSet.new(serialized_data.blocked_tasks),
      version: serialized_data.version,
      consistency_hash: serialized_data.consistency_hash,
      last_modified: DateTime.utc_now(),
      orders: orders,
      tasks: tasks,
      machines: machines,
      pools: pools,
      articles: articles
    }
    |> recalculate_derived_data()
  end

  # Fonctions privées

  defp calculate_initial_assignments(state) do
    # Assignation initiale simple : première machine compatible pour chaque tâche
    initial_assignments =
      state.tasks
      |> Enum.map(fn {task_id, task} ->
        compatible_machine = find_first_compatible_machine(state, task)
        {task_id, compatible_machine}
      end)
      |> Enum.reject(fn {_task_id, machine_id} -> is_nil(machine_id) end)
      |> Map.new()

    %{state | task_assignments: initial_assignments}
  end

  defp recalculate_state(state) do
    state
    |> calculate_task_start_times()
    |> calculate_machine_loads()
    |> calculate_critical_path()
    |> calculate_score()
    |> update_consistency_hash()
    |> update_last_modified()
  end

  defp recalculate_derived_data(state) do
    state
    |> calculate_task_start_times()
    |> calculate_machine_loads()
    |> calculate_critical_path()
  end

  defp calculate_task_start_times(state) do
    # Calcul des temps de début selon l'ordre d'index et les dépendances
    start_times =
      state.order_index
      |> Enum.flat_map(fn order_id ->
        order = state.orders[order_id]
        calculate_order_task_times(state, order)
      end)
      |> Map.new()

    %{state | task_start_times: start_times}
  end

  defp calculate_machine_loads(state) do
    # Calcul de la charge par machine basé sur les assignations
    loads =
      state.machines
      |> Map.keys()
      |> Enum.map(fn machine_id ->
        load = calculate_machine_load(state, machine_id)
        {machine_id, load}
      end)
      |> Map.new()

    %{state | machine_loads: loads}
  end

  defp calculate_critical_path(state) do
    # Identification des tâches sur le chemin critique
    critical_tasks = find_critical_path_tasks(state)
    %{state | critical_path_tasks: critical_tasks}
  end

  defp calculate_score(state) do
    # Calcul du score global selon la fonction multi-objectifs
    breakdown = JSS.Optimization.CostCalculator.calculate_full_score(state)
    total_score = Map.values(breakdown) |> Enum.sum()

    %{state |
      current_score: total_score,
      score_breakdown: breakdown
    }
  end

  defp increment_version(state) do
    %{state | version: state.version + 1}
  end

  defp update_last_modified(state) do
    %{state | last_modified: DateTime.utc_now()}
  end

  defp find_order_position(state, order_id) do
    case Enum.find_index(state.order_index, &(&1 == order_id)) do
      nil -> {:error, :not_found}
      index -> {:ok, index}
    end
  end

  defp is_compatible?(task, machine) do
    # Vérification de compatibilité entre tâche et machine
    task.required_machine_type == machine.machine_type
  end

  defp find_first_compatible_machine(state, task) do
    state.machines
    |> Enum.find(fn {_machine_id, machine} ->
      is_compatible?(task, machine)
    end)
    |> case do
      {machine_id, _machine} -> machine_id
      nil -> nil
    end
  end

  defp calculate_order_task_times(state, order) do
    # Calcul séquentiel des temps pour les tâches d'un ordre
    # TODO: Implémenter la logique de calcul temporel
    []
  end

  defp calculate_machine_load(state, machine_id) do
    # Calcul de la charge d'une machine
    # TODO: Implémenter le calcul de charge
    0.0
  end

  defp find_critical_path_tasks(state) do
    # Identification du chemin critique
    # TODO: Implémenter l'algorithme de chemin critique
    []
  end

  # Fonctions de validation

  defp validate_order_index(state) do
    expected_orders = MapSet.new(Map.keys(state.orders))
    actual_orders = MapSet.new(state.order_index)

    if MapSet.equal?(expected_orders, actual_orders) do
      :ok
    else
      {:error, :order_index_mismatch}
    end
  end

  defp validate_task_assignments(state) do
    invalid_assignments =
      state.task_assignments
      |> Enum.reject(fn {task_id, machine_id} ->
        Map.has_key?(state.tasks, task_id) and Map.has_key?(state.machines, machine_id)
      end)

    if Enum.empty?(invalid_assignments) do
      :ok
    else
      {:error, {:invalid_assignments, invalid_assignments}}
    end
  end

  defp validate_temporal_constraints(state) do
    # Validation des contraintes temporelles
    # TODO: Implémenter la validation temporelle
    :ok
  end

  defp validate_consistency_hash(state) do
    expected_hash = calculate_consistency_hash(state)

    if state.consistency_hash == expected_hash do
      :ok
    else
      {:error, :consistency_hash_mismatch}
    end
  end
end
