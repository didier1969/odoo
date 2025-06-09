defmodule JSS.Core.Machine do
  @moduledoc """
  Structure de données pour une machine de production.
  Définit les caractéristiques techniques, calendriers, et capacités.
  """

  @type machine_id :: String.t()
  @type machine_type :: String.t()
  @type pool_id :: String.t()
  @type article_id :: String.t()

  @type calendar_entry :: %{
    date: Date.t(),
    capacity_seconds: integer(),
    shift_start: Time.t(),
    shift_end: Time.t(),
    is_available: boolean()
  }

  @type setup_matrix_entry :: %{
    from_article: article_id(),
    to_article: article_id(),
    setup_time_seconds: integer()
  }

  @type t :: %__MODULE__{
    # Identification
    machine_id: machine_id(),
    machine_name: String.t(),
    machine_type: machine_type(),
    pool_id: pool_id(),

    # Caractéristiques techniques
    is_parallel_capable: boolean(),
    max_parallel_tasks: integer(),
    wait_time_seconds: integer(),

    # Coûts et tarification
    technology_rate_chf_per_hour: float(),
    setup_cost_multiplier: float(),

    # Calendrier et disponibilité
    calendar: %{Date.t() => calendar_entry()},
    maintenance_periods: [%{start: DateTime.t(), end: DateTime.t(), reason: String.t()}],

    # Matrice de changement d'outils
    setup_matrix: %{article_id() => %{article_id() => integer()}},
    current_article: article_id() | nil,

    # État opérationnel
    status: :available | :running | :setup | :maintenance | :down,
    last_status_change: DateTime.t(),

    # Métadonnées
    location: String.t(),
    operator_required: boolean(),
    quality_level: :standard | :high | :precision,
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  defstruct [
    :machine_id,
    :machine_name,
    :machine_type,
    :pool_id,
    :is_parallel_capable,
    :max_parallel_tasks,
    :wait_time_seconds,
    :technology_rate_chf_per_hour,
    :setup_cost_multiplier,
    :calendar,
    :maintenance_periods,
    :setup_matrix,
    :current_article,
    :status,
    :last_status_change,
    :location,
    :operator_required,
    :quality_level,
    :created_at,
    :updated_at
  ]

  @doc """
  Crée une nouvelle machine avec les paramètres par défaut.
  """
  def new(machine_id, machine_name, machine_type, pool_id, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      machine_id: machine_id,
      machine_name: machine_name,
      machine_type: machine_type,
      pool_id: pool_id,
      is_parallel_capable: Keyword.get(opts, :is_parallel_capable, false),
      max_parallel_tasks: Keyword.get(opts, :max_parallel_tasks, 1),
      wait_time_seconds: Keyword.get(opts, :wait_time_seconds, 0),
      technology_rate_chf_per_hour: Keyword.get(opts, :technology_rate_chf_per_hour, 100.0),
      setup_cost_multiplier: Keyword.get(opts, :setup_cost_multiplier, 1.0),
      calendar: %{},
      maintenance_periods: [],
      setup_matrix: %{},
      current_article: nil,
      status: :available,
      last_status_change: now,
      location: Keyword.get(opts, :location, ""),
      operator_required: Keyword.get(opts, :operator_required, false),
      quality_level: Keyword.get(opts, :quality_level, :standard),
      created_at: now,
      updated_at: now
    }
  end

  @doc """
  Met à jour le calendrier de la machine pour une période donnée.
  """
  def set_calendar(machine, start_date, end_date, daily_capacity_hours) do
    calendar_entries =
      Date.range(start_date, end_date)
      |> Enum.map(fn date ->
        {date, %{
          date: date,
          capacity_seconds: round(daily_capacity_hours * 3600),
          shift_start: ~T[07:00:00],
          shift_end: Time.add(~T[07:00:00], round(daily_capacity_hours * 3600), :second),
          is_available: daily_capacity_hours > 0
        }}
      end)
      |> Map.new()

    %{machine |
      calendar: Map.merge(machine.calendar, calendar_entries),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Définit ou met à jour un temps de changement d'outils.
  """
  def set_setup_time(machine, from_article, to_article, setup_time_seconds) do
    updated_matrix =
      machine.setup_matrix
      |> Map.put_new(from_article, %{})
      |> put_in([from_article, to_article], setup_time_seconds)

    %{machine |
      setup_matrix: updated_matrix,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Calcule le temps de changement d'outils entre deux articles.
  """
  def get_setup_time(machine, from_article, to_article) do
    cond do
      from_article == to_article -> 0
      is_nil(from_article) -> 0
      true ->
        machine.setup_matrix
        |> get_in([from_article, to_article])
        |> case do
          nil -> 0  # Pas de changement défini = pas de temps
          time -> time
        end
    end
  end

  @doc """
  Calcule la capacité disponible pour une date donnée.
  """
  def get_capacity(machine, date) do
    case Map.get(machine.calendar, date) do
      nil -> 0
      calendar_entry ->
        if calendar_entry.is_available do
          calendar_entry.capacity_seconds
        else
          0
        end
    end
  end

  @doc """
  Vérifie si la machine est disponible pour une période donnée.
  """
  def available_during?(machine, start_datetime, end_datetime) do
    # Vérification du calendrier quotidien
    start_date = DateTime.to_date(start_datetime)
    end_date = DateTime.to_date(end_datetime)

    calendar_available =
      Date.range(start_date, end_date)
      |> Enum.all?(fn date ->
        case Map.get(machine.calendar, date) do
          nil -> false
          entry -> entry.is_available
        end
      end)

    # Vérification des périodes de maintenance
    maintenance_free = not Enum.any?(machine.maintenance_periods, fn period ->
      DateTime.compare(start_datetime, period.end) == :lt and
      DateTime.compare(end_datetime, period.start) == :gt
    end)

    # Vérification du statut actuel
    status_available = machine.status in [:available, :running]

    calendar_available and maintenance_free and status_available
  end

  @doc """
  Met à jour le statut de la machine.
  """
  def set_status(machine, new_status, reason \\ nil) do
    %{machine |
      status: new_status,
      last_status_change: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Ajoute une période de maintenance planifiée.
  """
  def add_maintenance(machine, start_datetime, end_datetime, reason) do
    maintenance_period = %{
      start: start_datetime,
      end: end_datetime,
      reason: reason
    }

    %{machine |
      maintenance_periods: [maintenance_period | machine.maintenance_periods],
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Calcule le coût horaire effectif selon le niveau de qualité.
  """
  def effective_hourly_rate(machine) do
    base_rate = machine.technology_rate_chf_per_hour

    case machine.quality_level do
      :standard -> base_rate
      :high -> base_rate * 1.2
      :precision -> base_rate * 1.5
    end
  end

  @doc """
  Calcule le coût de changement d'outils.
  """
  def calculate_setup_cost(machine, from_article, to_article) do
    setup_time_seconds = get_setup_time(machine, from_article, to_article)
    setup_hours = setup_time_seconds / 3600.0
    hourly_rate = effective_hourly_rate(machine)

    setup_hours * hourly_rate * machine.setup_cost_multiplier
  end

  @doc """
  Vérifie si la machine peut traiter un type d'article donné.
  """
  def can_process_article?(machine, article) do
    # Vérification de base : le type de machine doit correspondre
    machine.machine_type == article.optimal_machine_type or
    machine.machine_type in (article.compatible_machine_types || [])
  end

  @doc """
  Calcule la charge actuelle de la machine (pourcentage).
  """
  def calculate_current_load(machine, assigned_tasks \\ []) do
    if Enum.empty?(assigned_tasks) do
      0.0
    else
      today = Date.utc_today()
      daily_capacity = get_capacity(machine, today)

      if daily_capacity == 0 do
        100.0  # Pas de capacité = charge maximale
      else
        total_task_time =
          assigned_tasks
          |> Enum.map(& &1.duration_seconds)
          |> Enum.sum()

        min(100.0, (total_task_time / daily_capacity) * 100.0)
      end
    end
  end

  @doc """
  Sérialise la machine pour stockage ou transmission.
  """
  def serialize(machine) do
    Map.take(machine, [
      :machine_id, :machine_name, :machine_type, :pool_id,
      :is_parallel_capable, :max_parallel_tasks, :wait_time_seconds,
      :technology_rate_chf_per_hour, :setup_cost_multiplier,
      :current_article, :status, :location, :operator_required,
      :quality_level
    ])
  end

  @doc """
  Valide la cohérence des données de la machine.
  """
  def validate(machine) do
    errors = []

    errors = if is_nil(machine.machine_id) or machine.machine_id == "",
      do: ["machine_id is required" | errors], else: errors

    errors = if machine.technology_rate_chf_per_hour < 0,
      do: ["technology_rate_chf_per_hour must be positive" | errors], else: errors

    errors = if machine.max_parallel_tasks < 1,
      do: ["max_parallel_tasks must be at least 1" | errors], else: errors

    errors = if machine.wait_time_seconds < 0,
      do: ["wait_time_seconds must be non-negative" | errors], else: errors

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
