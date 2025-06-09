defmodule JSS.Core.Task do
  @moduledoc """
  Structure de données pour une tâche de production.
  Définit les caractéristiques, contraintes, et état d'exécution.
  """

  @type task_id :: String.t()
  @type order_id :: String.t()
  @type machine_id :: String.t()
  @type machine_type :: String.t()
  @type article_id :: String.t()

  @type task_status ::
    :waiting |          # En attente d'assignation
    :assigned |         # Assignée à une machine
    :setup |           # Changement d'outils en cours
    :running |         # En cours d'exécution
    :paused |          # Mise en pause
    :completed |       # Terminée
    :cancelled |       # Annulée
    :blocked           # Bloquée par dépendance

  @type duration_spec ::
    {:unit_duration, integer()} |           # Durée fixe en secondes
    {:parallel_duration, float()}           # Durée en jours de travail (décimal)

  @type dependency :: %{
    predecessor_task_id: task_id(),
    dependency_type: :finish_to_start | :start_to_start | :finish_to_finish,
    lag_seconds: integer()
  }

  @type progress_update :: %{
    timestamp: DateTime.t(),
    progress_percent: float(),
    quantity_produced: integer(),
    operator_id: String.t(),
    notes: String.t()
  }

  @type t :: %__MODULE__{
    # Identification
    task_id: task_id(),
    task_name: String.t(),
    order_id: order_id(),
    sequence_number: integer(),

    # Spécifications techniques
    article_id: article_id(),
    required_machine_type: machine_type(),
    compatible_machine_types: [machine_type()],
    duration: duration_spec(),
    quantity_to_produce: integer(),

    # Contraintes et dépendances
    dependencies: [dependency()],
    earliest_start: DateTime.t() | nil,
    latest_finish: DateTime.t() | nil,
    is_critical: boolean(),

    # Assignation et planification
    assigned_machine_id: machine_id() | nil,
    planned_start: DateTime.t() | nil,
    planned_end: DateTime.t() | nil,
    actual_start: DateTime.t() | nil,
    actual_end: DateTime.t() | nil,

    # État et progression
    status: task_status(),
    progress_percent: float(),
    quantity_produced: integer(),
    progress_history: [progress_update()],

    # Coûts et performance
    estimated_cost: float(),
    actual_cost: float() | nil,
    setup_time_seconds: integer(),

    # Contraintes spéciales
    priority: :low | :normal | :high | :urgent,
    is_immutable: boolean(),
    can_be_split: boolean(),
    requires_operator: boolean(),
    quality_requirements: [String.t()],

    # Métadonnées
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    locked_until: DateTime.t() | nil,
    notes: String.t()
  }

  defstruct [
    :task_id,
    :task_name,
    :order_id,
    :sequence_number,
    :article_id,
    :required_machine_type,
    :compatible_machine_types,
    :duration,
    :quantity_to_produce,
    :dependencies,
    :earliest_start,
    :latest_finish,
    :is_critical,
    :assigned_machine_id,
    :planned_start,
    :planned_end,
    :actual_start,
    :actual_end,
    :status,
    :progress_percent,
    :quantity_produced,
    :progress_history,
    :estimated_cost,
    :actual_cost,
    :setup_time_seconds,
    :priority,
    :is_immutable,
    :can_be_split,
    :requires_operator,
    :quality_requirements,
    :created_at,
    :updated_at,
    :locked_until,
    :notes
  ]

  @doc """
  Crée une nouvelle tâche avec les paramètres par défaut.
  """
  def new(task_id, task_name, order_id, article_id, required_machine_type, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      task_id: task_id,
      task_name: task_name,
      order_id: order_id,
      sequence_number: Keyword.get(opts, :sequence_number, 1),
      article_id: article_id,
      required_machine_type: required_machine_type,
      compatible_machine_types: Keyword.get(opts, :compatible_machine_types, []),
      duration: Keyword.get(opts, :duration, {:unit_duration, 3600}),
      quantity_to_produce: Keyword.get(opts, :quantity_to_produce, 1),
      dependencies: Keyword.get(opts, :dependencies, []),
      earliest_start: Keyword.get(opts, :earliest_start),
      latest_finish: Keyword.get(opts, :latest_finish),
      is_critical: false,
      assigned_machine_id: nil,
      planned_start: nil,
      planned_end: nil,
      actual_start: nil,
      actual_end: nil,
      status: :waiting,
      progress_percent: 0.0,
      quantity_produced: 0,
      progress_history: [],
      estimated_cost: 0.0,
      actual_cost: nil,
      setup_time_seconds: 0,
      priority: Keyword.get(opts, :priority, :normal),
      is_immutable: false,
      can_be_split: Keyword.get(opts, :can_be_split, false),
      requires_operator: Keyword.get(opts, :requires_operator, false),
      quality_requirements: Keyword.get(opts, :quality_requirements, []),
      created_at: now,
      updated_at: now,
      locked_until: nil,
      notes: Keyword.get(opts, :notes, "")
    }
  end

  @doc """
  Assigne la tâche à une machine spécifique.
  """
  def assign_to_machine(task, machine_id, planned_start, planned_end) do
    %{task |
      assigned_machine_id: machine_id,
      planned_start: planned_start,
      planned_end: planned_end,
      status: if(task.status == :waiting, do: :assigned, else: task.status),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Démarre l'exécution de la tâche avec un timestamp opérateur.
  """
  def start_execution(task, operator_id \\ "system") do
    if task.status in [:assigned, :setup] do
      progress_update = %{
        timestamp: DateTime.utc_now(),
        progress_percent: 0.0,
        quantity_produced: 0,
        operator_id: operator_id,
        notes: "Task started"
      }

      %{task |
        status: :running,
        actual_start: DateTime.utc_now(),
        progress_history: [progress_update | task.progress_history],
        is_immutable: true,
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :invalid_status_transition}
    end
  end

  @doc """
  Met à jour la progression de la tâche.
  """
  def update_progress(task, progress_percent, quantity_produced, operator_id, notes \\ "") do
    if task.status == :running do
      progress_update = %{
        timestamp: DateTime.utc_now(),
        progress_percent: progress_percent,
        quantity_produced: quantity_produced,
        operator_id: operator_id,
        notes: notes
      }

      new_status = if progress_percent >= 100.0, do: :completed, else: :running

      %{task |
        progress_percent: progress_percent,
        quantity_produced: quantity_produced,
        status: new_status,
        actual_end: if(new_status == :completed, do: DateTime.utc_now(), else: nil),
        progress_history: [progress_update | task.progress_history],
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :task_not_running}
    end
  end

  @doc """
  Marque la tâche comme terminée.
  """
  def complete(task, operator_id \\ "system", final_quantity \\ nil) do
    if task.status in [:running, :paused] do
      final_qty = final_quantity || task.quantity_to_produce

      progress_update = %{
        timestamp: DateTime.utc_now(),
        progress_percent: 100.0,
        quantity_produced: final_qty,
        operator_id: operator_id,
        notes: "Task completed"
      }

      %{task |
        status: :completed,
        progress_percent: 100.0,
        quantity_produced: final_qty,
        actual_end: DateTime.utc_now(),
        progress_history: [progress_update | task.progress_history],
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :invalid_status_for_completion}
    end
  end

  @doc """
  Met la tâche en pause.
  """
  def pause(task, reason, operator_id \\ "system") do
    if task.status == :running do
      progress_update = %{
        timestamp: DateTime.utc_now(),
        progress_percent: task.progress_percent,
        quantity_produced: task.quantity_produced,
        operator_id: operator_id,
        notes: "Task paused: #{reason}"
      }

      %{task |
        status: :paused,
        progress_history: [progress_update | task.progress_history],
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :task_not_running}
    end
  end

  @doc """
  Reprend l'exécution d'une tâche en pause.
  """
  def resume(task, operator_id \\ "system") do
    if task.status == :paused do
      progress_update = %{
        timestamp: DateTime.utc_now(),
        progress_percent: task.progress_percent,
        quantity_produced: task.quantity_produced,
        operator_id: operator_id,
        notes: "Task resumed"
      }

      %{task |
        status: :running,
        progress_history: [progress_update | task.progress_history],
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :task_not_paused}
    end
  end

  @doc """
  Calcule la durée en secondes selon le type de tâche.
  """
  def get_duration_seconds(task) do
    case task.duration do
      {:unit_duration, seconds} -> seconds
      {:parallel_duration, days} -> round(days * 24 * 3600)
    end
  end

  @doc """
  Vérifie si la tâche peut être démarrée selon ses dépendances.
  """
  def can_start?(task, completed_tasks) do
    if task.status != :assigned do
      false
    else
      completed_task_ids = MapSet.new(completed_tasks)

      Enum.all?(task.dependencies, fn dep ->
        case dep.dependency_type do
          :finish_to_start ->
            MapSet.member?(completed_task_ids, dep.predecessor_task_id)
          :start_to_start ->
            # Pour simplifier, on considère que start_to_start = finish_to_start
            MapSet.member?(completed_task_ids, dep.predecessor_task_id)
          :finish_to_finish ->
            # Plus complexe, nécessite de vérifier la fin simultanée
            MapSet.member?(completed_task_ids, dep.predecessor_task_id)
        end
      end)
    end
  end

  @doc """
  Calcule le délai ou l'avance par rapport à la date prévue.
  """
  def calculate_delay(task, target_date) do
    case {task.actual_end, task.planned_end} do
      {actual, _} when not is_nil(actual) ->
        # Tâche terminée : délai = actual_end - target_date
        DateTime.diff(actual, target_date, :second)

      {nil, planned} when not is_nil(planned) ->
        # Tâche planifiée : délai = planned_end - target_date
        DateTime.diff(planned, target_date, :second)

      _ ->
        # Pas de date de référence
        0
    end
  end

  @doc """
  Vérifie si la tâche est compatible avec un type de machine.
  """
  def compatible_with_machine_type?(task, machine_type) do
    task.required_machine_type == machine_type or
    machine_type in (task.compatible_machine_types || [])
  end

  @doc """
  Calcule le coût estimé de la tâche sur une machine donnée.
  """
  def calculate_estimated_cost(task, machine) do
    duration_hours = get_duration_seconds(task) / 3600.0
    base_cost = duration_hours * machine.technology_rate_chf_per_hour

    # Ajout du coût de changement d'outils si nécessaire
    setup_cost = if task.setup_time_seconds > 0 do
      setup_hours = task.setup_time_seconds / 3600.0
      setup_hours * machine.technology_rate_chf_per_hour * machine.setup_cost_multiplier
    else
      0.0
    end

    base_cost + setup_cost
  end

  @doc """
  Détermine si la tâche est en retard.
  """
  def is_delayed?(task, reference_time \\ nil) do
    ref_time = reference_time || DateTime.utc_now()

    case task.status do
      :completed ->
        case {task.actual_end, task.planned_end} do
          {actual, planned} when not is_nil(actual) and not is_nil(planned) ->
            DateTime.compare(actual, planned) == :gt
          _ -> false
        end

      status when status in [:running, :paused, :assigned] ->
        case task.planned_end do
          nil -> false
          planned -> DateTime.compare(ref_time, planned) == :gt
        end

      _ -> false
    end
  end

  @doc """
  Ajoute une dépendance à la tâche.
  """
  def add_dependency(task, predecessor_task_id, dependency_type \\ :finish_to_start, lag_seconds \\ 0) do
    dependency = %{
      predecessor_task_id: predecessor_task_id,
      dependency_type: dependency_type,
      lag_seconds: lag_seconds
    }

    %{task |
      dependencies: [dependency | task.dependencies],
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Verrouille temporairement la tâche pour éviter les modifications.
  """
  def lock(task, until_datetime) do
    %{task |
      locked_until: until_datetime,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Vérifie si la tâche est actuellement verrouillée.
  """
  def locked?(task) do
    case task.locked_until do
      nil -> false
      until_time -> DateTime.compare(DateTime.utc_now(), until_time) == :lt
    end
  end

  @doc """
  Sérialise la tâche pour stockage ou transmission.
  """
  def serialize(task) do
    Map.take(task, [
      :task_id, :task_name, :order_id, :sequence_number,
      :article_id, :required_machine_type, :duration,
      :quantity_to_produce, :dependencies, :status,
      :progress_percent, :assigned_machine_id,
      :planned_start, :planned_end, :priority,
      :is_immutable, :notes
    ])
  end

  @doc """
  Valide la cohérence des données de la tâche.
  """
  def validate(task) do
    errors = []

    errors = if is_nil(task.task_id) or task.task_id == "",
      do: ["task_id is required" | errors], else: errors

    errors = if is_nil(task.order_id) or task.order_id == "",
      do: ["order_id is required" | errors], else: errors

    errors = if task.sequence_number < 1,
      do: ["sequence_number must be positive" | errors], else: errors

    errors = if task.quantity_to_produce < 1,
      do: ["quantity_to_produce must be positive" | errors], else: errors

    errors = if task.progress_percent < 0.0 or task.progress_percent > 100.0,
      do: ["progress_percent must be between 0 and 100" | errors], else: errors

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
