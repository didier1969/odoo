defmodule JSS.Core.Order do
  @moduledoc """
  Structure de données pour une commande de production.
  Regroupe les tâches séquentielles et définit les contraintes globales.
  """

  @type order_id :: String.t()
  @type customer_id :: String.t()
  @type task_id :: String.t()

  @type order_status ::
    :draft |            # Brouillon, pas encore confirmé
    :confirmed |        # Confirmé, prêt pour planification
    :planned |          # Planifié dans le système
    :in_progress |      # Au moins une tâche démarrée
    :completed |        # Toutes les tâches terminées
    :cancelled |        # Annulé
    :on_hold           # Suspendu temporairement

  @type priority_level :: :low | :normal | :high | :urgent | :critical

  @type delivery_constraint :: %{
    delivery_date: DateTime.t(),
    delivery_location: String.t(),
    is_hard_constraint: boolean(),
    penalty_per_day: float()
  }

  @type quality_constraint :: %{
    quality_level: :standard | :high | :precision,
    inspection_required: boolean(),
    certifications_needed: [String.t()]
  }

  @type t :: %__MODULE__{
    # Identification
    order_id: order_id(),
    order_number: String.t(),
    customer_id: customer_id(),
    customer_name: String.t(),

    # Position dans la séquence globale
    index_position: integer(),
    original_position: integer(),

    # Contenu de la commande
    task_ids: [task_id()],
    total_quantity: integer(),

    # Contraintes temporelles
    order_date: DateTime.t(),
    requested_delivery_date: DateTime.t(),
    confirmed_delivery_date: DateTime.t() | nil,
    earliest_start_date: DateTime.t() | nil,

    # Priorité et urgence
    priority: priority_level(),
    is_rush_order: boolean(),
    customer_priority_score: float(),

    # Contraintes de livraison
    delivery_constraints: delivery_constraint(),

    # Contraintes de qualité
    quality_constraints: quality_constraint(),

    # État et progression
    status: order_status(),
    completion_percent: float(),
    actual_start_date: DateTime.t() | nil,
    actual_completion_date: DateTime.t() | nil,

    # Coûts et performance
    estimated_total_cost: float(),
    actual_total_cost: float() | nil,
    estimated_duration_hours: float(),
    actual_duration_hours: float() | nil,

    # Contraintes spéciales
    requires_special_setup: boolean(),
    material_constraints: [String.t()],
    resource_constraints: [String.t()],
    can_be_split: boolean(),

    # Tracking et notifications
    customer_notifications_enabled: boolean(),
    last_customer_update: DateTime.t() | nil,
    milestone_alerts: [String.t()],

    # Métadonnées
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    created_by: String.t(),
    notes: String.t(),

    # Relations
    parent_order_id: order_id() | nil,
    child_order_ids: [order_id()],
    related_order_ids: [order_id()]
  }

  defstruct [
    :order_id,
    :order_number,
    :customer_id,
    :customer_name,
    :index_position,
    :original_position,
    :task_ids,
    :total_quantity,
    :order_date,
    :requested_delivery_date,
    :confirmed_delivery_date,
    :earliest_start_date,
    :priority,
    :is_rush_order,
    :customer_priority_score,
    :delivery_constraints,
    :quality_constraints,
    :status,
    :completion_percent,
    :actual_start_date,
    :actual_completion_date,
    :estimated_total_cost,
    :actual_total_cost,
    :estimated_duration_hours,
    :actual_duration_hours,
    :requires_special_setup,
    :material_constraints,
    :resource_constraints,
    :can_be_split,
    :customer_notifications_enabled,
    :last_customer_update,
    :milestone_alerts,
    :created_at,
    :updated_at,
    :created_by,
    :notes,
    :parent_order_id,
    :child_order_ids,
    :related_order_ids
  ]

  @doc """
  Crée une nouvelle commande avec les paramètres par défaut.
  """
  def new(order_id, order_number, customer_id, customer_name, opts \\ []) do
    now = DateTime.utc_now()
    delivery_date = Keyword.get(opts, :requested_delivery_date, DateTime.add(now, 30 * 24 * 3600, :second))

    %__MODULE__{
      order_id: order_id,
      order_number: order_number,
      customer_id: customer_id,
      customer_name: customer_name,
      index_position: Keyword.get(opts, :index_position, 0),
      original_position: Keyword.get(opts, :index_position, 0),
      task_ids: [],
      total_quantity: Keyword.get(opts, :total_quantity, 1),
      order_date: Keyword.get(opts, :order_date, now),
      requested_delivery_date: delivery_date,
      confirmed_delivery_date: nil,
      earliest_start_date: Keyword.get(opts, :earliest_start_date),
      priority: Keyword.get(opts, :priority, :normal),
      is_rush_order: Keyword.get(opts, :is_rush_order, false),
      customer_priority_score: Keyword.get(opts, :customer_priority_score, 1.0),
      delivery_constraints: %{
        delivery_date: delivery_date,
        delivery_location: Keyword.get(opts, :delivery_location, ""),
        is_hard_constraint: Keyword.get(opts, :is_hard_constraint, true),
        penalty_per_day: Keyword.get(opts, :penalty_per_day, 0.0)
      },
      quality_constraints: %{
        quality_level: Keyword.get(opts, :quality_level, :standard),
        inspection_required: Keyword.get(opts, :inspection_required, false),
        certifications_needed: Keyword.get(opts, :certifications_needed, [])
      },
      status: :draft,
      completion_percent: 0.0,
      actual_start_date: nil,
      actual_completion_date: nil,
      estimated_total_cost: 0.0,
      actual_total_cost: nil,
      estimated_duration_hours: 0.0,
      actual_duration_hours: nil,
      requires_special_setup: Keyword.get(opts, :requires_special_setup, false),
      material_constraints: Keyword.get(opts, :material_constraints, []),
      resource_constraints: Keyword.get(opts, :resource_constraints, []),
      can_be_split: Keyword.get(opts, :can_be_split, false),
      customer_notifications_enabled: Keyword.get(opts, :customer_notifications_enabled, true),
      last_customer_update: nil,
      milestone_alerts: [],
      created_at: now,
      updated_at: now,
      created_by: Keyword.get(opts, :created_by, "system"),
      notes: Keyword.get(opts, :notes, ""),
      parent_order_id: Keyword.get(opts, :parent_order_id),
      child_order_ids: [],
      related_order_ids: []
    }
  end

  @doc """
  Ajoute une tâche à la commande.
  """
  def add_task(order, task_id) do
    if task_id in order.task_ids do
      {:error, :task_already_exists}
    else
      %{order |
        task_ids: order.task_ids ++ [task_id],
        updated_at: DateTime.utc_now()
      }
    end
  end

  @doc """
  Retire une tâche de la commande.
  """
  def remove_task(order, task_id) do
    if task_id in order.task_ids do
      %{order |
        task_ids: List.delete(order.task_ids, task_id),
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :task_not_found}
    end
  end

  @doc """
  Met à jour la position dans l'index global.
  """
  def set_index_position(order, new_position) do
    %{order |
      index_position: new_position,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Change le statut de la commande.
  """
  def set_status(order, new_status) do
    if valid_status_transition?(order.status, new_status) do
      updated_order = %{order |
        status: new_status,
        updated_at: DateTime.utc_now()
      }

      # Actions automatiques selon le nouveau statut
      case new_status do
        :in_progress ->
          %{updated_order | actual_start_date: DateTime.utc_now()}

        :completed ->
          %{updated_order |
            actual_completion_date: DateTime.utc_now(),
            completion_percent: 100.0
          }

        _ ->
          updated_order
      end
    else
      {:error, {:invalid_status_transition, order.status, new_status}}
    end
  end

  @doc """
  Met à jour la progression de la commande basée sur ses tâches.
  """
  def update_completion(order, completed_tasks, total_tasks) do
    new_completion = if total_tasks > 0 do
      (completed_tasks / total_tasks) * 100.0
    else
      0.0
    end

    new_status = cond do
      new_completion == 0.0 and order.status == :in_progress -> :planned
      new_completion > 0.0 and new_completion < 100.0 -> :in_progress
      new_completion == 100.0 -> :completed
      true -> order.status
    end

    %{order |
      completion_percent: new_completion,
      status: new_status,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Calcule la priorité effective basée sur plusieurs facteurs.
  """
  def calculate_effective_priority(order) do
    base_priority = case order.priority do
      :low -> 1.0
      :normal -> 2.0
      :high -> 3.0
      :urgent -> 4.0
      :critical -> 5.0
    end

    # Facteur de délai (plus proche de la livraison = plus prioritaire)
    now = DateTime.utc_now()
    days_until_delivery = DateTime.diff(order.requested_delivery_date, now, :day)
    urgency_factor = max(0.1, 1.0 / max(1, days_until_delivery))

    # Facteur client
    customer_factor = order.customer_priority_score

    # Facteur rush
    rush_factor = if order.is_rush_order, do: 1.5, else: 1.0

    base_priority * urgency_factor * customer_factor * rush_factor
  end

  @doc """
  Vérifie si la commande est en retard.
  """
  def is_overdue?(order, reference_time \\ nil) do
    ref_time = reference_time || DateTime.utc_now()

    case order.status do
      :completed ->
        case order.actual_completion_date do
          nil -> false
          actual -> DateTime.compare(actual, order.requested_delivery_date) == :gt
        end

      status when status in [:planned, :in_progress] ->
        DateTime.compare(ref_time, order.requested_delivery_date) == :gt

      _ -> false
    end
  end

  @doc """
  Calcule le délai de livraison (positif = retard, négatif = avance).
  """
  def calculate_delivery_delay(order) do
    case {order.status, order.actual_completion_date} do
      {:completed, actual} when not is_nil(actual) ->
        DateTime.diff(actual, order.requested_delivery_date, :day)

      _ ->
        # Estimation basée sur la date actuelle pour les commandes non terminées
        now = DateTime.utc_now()
        DateTime.diff(now, order.requested_delivery_date, :day)
    end
  end

  @doc """
  Confirme la date de livraison et met à jour les contraintes.
  """
  def confirm_delivery_date(order, confirmed_date, update_penalty \\ nil) do
    updated_constraints = %{order.delivery_constraints |
      delivery_date: confirmed_date
    }

    updated_constraints = if update_penalty do
      %{updated_constraints | penalty_per_day: update_penalty}
    else
      updated_constraints
    end

    %{order |
      confirmed_delivery_date: confirmed_date,
      delivery_constraints: updated_constraints,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Ajoute une commande enfant (sous-commande).
  """
  def add_child_order(order, child_order_id) do
    if child_order_id in order.child_order_ids do
      {:error, :child_already_exists}
    else
      %{order |
        child_order_ids: [child_order_id | order.child_order_ids],
        updated_at: DateTime.utc_now()
      }
    end
  end

  @doc """
  Lie une commande connexe.
  """
  def add_related_order(order, related_order_id) do
    if related_order_id in order.related_order_ids do
      {:error, :relation_already_exists}
    else
      %{order |
        related_order_ids: [related_order_id | order.related_order_ids],
        updated_at: DateTime.utc_now()
      }
    end
  end

  @doc """
  Met à jour les coûts estimés et réels.
  """
  def update_costs(order, estimated_cost, actual_cost \\ nil) do
    %{order |
      estimated_total_cost: estimated_cost,
      actual_total_cost: actual_cost,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Ajoute une alerte de milestone.
  """
  def add_milestone_alert(order, milestone_description) do
    %{order |
      milestone_alerts: [milestone_description | order.milestone_alerts],
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Enregistre une notification client.
  """
  def record_customer_notification(order) do
    %{order |
      last_customer_update: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Vérifie si une notification client est nécessaire.
  """
  def needs_customer_notification?(order, notification_interval_hours \\ 24) do
    if not order.customer_notifications_enabled do
      false
    else
      case order.last_customer_update do
        nil -> true
        last_update ->
          hours_since_update = DateTime.diff(DateTime.utc_now(), last_update, :hour)
          hours_since_update >= notification_interval_hours
      end
    end
  end

  @doc """
  Calcule les jours de travail restants jusqu'à la livraison.
  """
  def working_days_until_delivery(order, working_days_per_week \\ 5) do
    now = DateTime.utc_now()
    total_days = DateTime.diff(order.requested_delivery_date, now, :day)

    # Approximation simple : (jours totaux / 7) * jours ouvrables par semaine
    working_days = (total_days / 7) * working_days_per_week
    max(0, round(working_days))
  end

  @doc """
  Vérifie si la commande peut être divisée en sous-commandes.
  """
  def can_split?(order) do
    order.can_be_split and
    order.status in [:draft, :confirmed, :planned] and
    length(order.task_ids) > 1
  end

  @doc """
  Divise la commande en plusieurs sous-commandes.
  """
  def split_order(order, task_groups, split_strategy \\ :sequential) do
    if can_split?(order) do
      child_orders =
        task_groups
        |> Enum.with_index()
        |> Enum.map(fn {task_group, index} ->
          child_id = "#{order.order_id}_split_#{index + 1}"
          child_number = "#{order.order_number}-#{index + 1}"

          %{order |
            order_id: child_id,
            order_number: child_number,
            task_ids: task_group,
            parent_order_id: order.order_id,
            child_order_ids: [],
            index_position: calculate_split_position(order, index, split_strategy),
            created_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        end)

      parent_order = %{order |
        task_ids: [],
        child_order_ids: Enum.map(child_orders, & &1.order_id),
        status: :completed,  # Parent devient un container
        updated_at: DateTime.utc_now()
      }

      {:ok, parent_order, child_orders}
    else
      {:error, :cannot_split_order}
    end
  end

  @doc """
  Fusionne des commandes enfants en remontant au parent.
  """
  def merge_child_orders(parent_order, child_orders) do
    if parent_order.order_id in Enum.map(child_orders, & &1.parent_order_id) do
      merged_task_ids = Enum.flat_map(child_orders, & &1.task_ids)

      %{parent_order |
        task_ids: merged_task_ids,
        child_order_ids: [],
        status: :planned,
        completion_percent: calculate_merged_completion(child_orders),
        updated_at: DateTime.utc_now()
      }
    else
      {:error, :invalid_parent_child_relationship}
    end
  end

  @doc """
  Sérialise la commande pour stockage ou transmission.
  """
  def serialize(order) do
    Map.take(order, [
      :order_id, :order_number, :customer_id, :customer_name,
      :index_position, :task_ids, :total_quantity,
      :order_date, :requested_delivery_date, :priority,
      :is_rush_order, :delivery_constraints, :quality_constraints,
      :status, :completion_percent, :estimated_total_cost,
      :requires_special_setup, :can_be_split, :notes
    ])
  end

  @doc """
  Valide la cohérence des données de la commande.
  """
  def validate(order) do
    errors = []

    errors = if is_nil(order.order_id) or order.order_id == "",
      do: ["order_id is required" | errors], else: errors

    errors = if is_nil(order.customer_id) or order.customer_id == "",
      do: ["customer_id is required" | errors], else: errors

    errors = if order.total_quantity < 1,
      do: ["total_quantity must be positive" | errors], else: errors

    errors = if order.completion_percent < 0.0 or order.completion_percent > 100.0,
      do: ["completion_percent must be between 0 and 100" | errors], else: errors

    errors = if DateTime.compare(order.requested_delivery_date, order.order_date) == :lt,
      do: ["delivery_date cannot be before order_date" | errors], else: errors

    errors = if order.index_position < 0,
      do: ["index_position must be non-negative" | errors], else: errors

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # Fonctions privées

  defp valid_status_transition?(current_status, new_status) do
    valid_transitions = %{
      :draft => [:confirmed, :cancelled],
      :confirmed => [:planned, :on_hold, :cancelled],
      :planned => [:in_progress, :on_hold, :cancelled],
      :in_progress => [:completed, :on_hold, :cancelled],
      :completed => [],  # État final
      :cancelled => [],  # État final
      :on_hold => [:planned, :cancelled]
    }

    new_status in Map.get(valid_transitions, current_status, [])
  end

  defp calculate_split_position(parent_order, split_index, strategy) do
    case strategy do
      :sequential ->
        # Positions séquentielles après le parent
        parent_order.index_position + split_index + 1

      :parallel ->
        # Même position que le parent (traitement parallèle)
        parent_order.index_position

      :priority_based ->
        # Position basée sur la priorité des tâches (plus complexe)
        parent_order.index_position + split_index
    end
  end

  defp calculate_merged_completion(child_orders) do
    if Enum.empty?(child_orders) do
      0.0
    else
      total_completion = Enum.sum(Enum.map(child_orders, & &1.completion_percent))
      total_completion / length(child_orders)
    end
  end
end
