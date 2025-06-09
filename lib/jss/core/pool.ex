defmodule JSS.Core.Pool do
  @moduledoc """
  Structure de données pour un pool de machines.
  Représente un groupement de machines par spécialisation métier.
  """

  @type pool_id :: String.t()
  @type machine_id :: String.t()
  @type machine_type :: String.t()
  @type article_id :: String.t()

  @type load_balancing_strategy ::
    :round_robin |          # Répartition circulaire
    :least_loaded |         # Machine la moins chargée
    :shortest_queue |       # Queue la plus courte
    :random |              # Aléatoire
    :priority_based        # Basé sur la priorité des tâches

  @type t :: %__MODULE__{
    # Identification
    pool_id: pool_id(),
    pool_name: String.t(),
    description: String.t(),

    # Hiérarchie et spécialisation
    hierarchy_level: integer(),
    parent_pool_ids: [pool_id()],
    child_pool_ids: [pool_id()],
    specialization_tags: [String.t()],

    # Machines du pool
    machines_by_type: %{machine_type() => [machine_id()]},
    total_machine_count: integer(),

    # Articles supportés
    optimal_articles: [article_id()],          # Articles optimaux pour ce pool
    compatible_articles: [article_id()],       # Articles compatibles

    # Tarification et coûts
    technology_rates: %{machine_type() => float()},  # CHF/heure par type
    pool_overhead_rate: float(),                     # Surcoût du pool
    spillover_penalty_rate: float(),                 # Pénalité spillover vers parent

    # Gestion de charge
    load_balancing_strategy: load_balancing_strategy(),
    max_capacity_percent: float(),
    current_load_percent: float(),

    # Contraintes opérationnelles
    operating_hours: %{start_time: Time.t(), end_time: Time.t()},
    weekend_operations: boolean(),
    shift_patterns: [String.t()],

    # Performance et métriques
    avg_setup_time_seconds: integer(),
    efficiency_rating: float(),
    quality_score: float(),

    # Métadonnées
    location: String.t(),
    manager: String.t(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    is_active: boolean()
  }

  defstruct [
    :pool_id,
    :pool_name,
    :description,
    :hierarchy_level,
    :parent_pool_ids,
    :child_pool_ids,
    :specialization_tags,
    :machines_by_type,
    :total_machine_count,
    :optimal_articles,
    :compatible_articles,
    :technology_rates,
    :pool_overhead_rate,
    :spillover_penalty_rate,
    :load_balancing_strategy,
    :max_capacity_percent,
    :current_load_percent,
    :operating_hours,
    :weekend_operations,
    :shift_patterns,
    :avg_setup_time_seconds,
    :efficiency_rating,
    :quality_score,
    :location,
    :manager,
    :created_at,
    :updated_at,
    :is_active
  ]

  @doc """
  Crée un nouveau pool avec les paramètres par défaut.
  """
  def new(pool_id, pool_name, hierarchy_level, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      pool_id: pool_id,
      pool_name: pool_name,
      description: Keyword.get(opts, :description, ""),
      hierarchy_level: hierarchy_level,
      parent_pool_ids: Keyword.get(opts, :parent_pool_ids, []),
      child_pool_ids: [],
      specialization_tags: Keyword.get(opts, :specialization_tags, []),
      machines_by_type: %{},
      total_machine_count: 0,
      optimal_articles: Keyword.get(opts, :optimal_articles, []),
      compatible_articles: Keyword.get(opts, :compatible_articles, []),
      technology_rates: %{},
      pool_overhead_rate: Keyword.get(opts, :pool_overhead_rate, 0.0),
      spillover_penalty_rate: Keyword.get(opts, :spillover_penalty_rate, 1.2),
      load_balancing_strategy: Keyword.get(opts, :load_balancing_strategy, :least_loaded),
      max_capacity_percent: Keyword.get(opts, :max_capacity_percent, 90.0),
      current_load_percent: 0.0,
      operating_hours: Keyword.get(opts, :operating_hours, %{start_time: ~T[07:00:00], end_time: ~T[19:00:00]}),
      weekend_operations: Keyword.get(opts, :weekend_operations, false),
      shift_patterns: Keyword.get(opts, :shift_patterns, ["day_shift"]),
      avg_setup_time_seconds: Keyword.get(opts, :avg_setup_time_seconds, 1800),
      efficiency_rating: Keyword.get(opts, :efficiency_rating, 1.0),
      quality_score: Keyword.get(opts, :quality_score, 1.0),
      location: Keyword.get(opts, :location, ""),
      manager: Keyword.get(opts, :manager, ""),
      created_at: now,
      updated_at: now,
      is_active: true
    }
  end

  @doc """
  Ajoute une machine au pool.
  """
  def add_machine(pool, machine_id, machine_type) do
    updated_machines =
      pool.machines_by_type
      |> Map.update(machine_type, [machine_id], fn machines ->
        if machine_id in machines do
          machines
        else
          [machine_id | machines]
        end
      end)

    %{pool |
      machines_by_type: updated_machines,
      total_machine_count: calculate_total_machines(updated_machines),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Retire une machine du pool.
  """
  def remove_machine(pool, machine_id, machine_type) do
    updated_machines =
      pool.machines_by_type
      |> Map.update(machine_type, [], fn machines ->
        List.delete(machines, machine_id)
      end)
      |> Enum.reject(fn {_type, machines} -> Enum.empty?(machines) end)
      |> Map.new()

    %{pool |
      machines_by_type: updated_machines,
      total_machine_count: calculate_total_machines(updated_machines),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Vérifie si le pool peut traiter un article donné.
  """
  def can_handle_article?(pool, article_id) do
    article_id in pool.optimal_articles or article_id in pool.compatible_articles
  end

  @doc """
  Calcule le coût effectif pour traiter un article.
  """
  def calculate_article_cost(pool, article, machine_type, duration_hours) do
    base_rate = Map.get(pool.technology_rates, machine_type, 0.0)
    overhead = pool.pool_overhead_rate

    cost_multiplier = cond do
      article.article_id in pool.optimal_articles -> 1.0
      article.article_id in pool.compatible_articles -> pool.spillover_penalty_rate
      true -> pool.spillover_penalty_rate * 1.5  # Pénalité supplémentaire
    end

    (base_rate + overhead) * duration_hours * cost_multiplier
  end

  @doc """
  Met à jour la charge courante du pool.
  """
  def update_load(pool, new_load_percent) do
    %{pool |
      current_load_percent: max(0.0, min(100.0, new_load_percent)),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Vérifie si le pool a de la capacité disponible.
  """
  def has_capacity?(pool, required_capacity_percent \\ 0.0) do
    pool.is_active and
    (pool.current_load_percent + required_capacity_percent) <= pool.max_capacity_percent
  end

  @doc """
  Sélectionne la meilleure machine selon la stratégie de load balancing.
  """
  def select_machine(pool, machine_type, machine_loads \\ %{}) do
    available_machines = Map.get(pool.machines_by_type, machine_type, [])

    case {available_machines, pool.load_balancing_strategy} do
      {[], _} -> {:error, :no_machines_available}
      {machines, :least_loaded} -> select_least_loaded_machine(machines, machine_loads)
      {machines, :round_robin} -> select_round_robin_machine(machines)
      {machines, :random} -> {:ok, Enum.random(machines)}
      {machines, _} -> {:ok, hd(machines)}  # Fallback
    end
  end

  # Fonctions privées pour sélection de machines
  defp select_least_loaded_machine(machines, machine_loads) do
    machine_with_load = machines
    |> Enum.map(fn machine_id ->
      load = Map.get(machine_loads, machine_id, 0.0)
      {machine_id, load}
    end)
    |> Enum.min_by(fn {_id, load} -> load end)

    {:ok, elem(machine_with_load, 0)}
  end

  defp select_round_robin_machine(machines) do
    # Simple round robin basé sur l'ordre
    {:ok, hd(machines)}
  end

  defp calculate_total_machines(machines_by_type) do
    machines_by_type
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end
end
