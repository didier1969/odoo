defmodule JSS.Core.Article do
  @moduledoc """
  Structure de données pour un article à produire.
  Définit les caractéristiques techniques et contraintes de production.
  """

  @type article_id :: String.t()
  @type machine_type :: String.t()
  @type pool_id :: String.t()

  @type complexity_level :: :simple | :standard | :complex | :precision

  @type production_spec :: %{
    standard_duration_seconds: integer(),
    setup_complexity: complexity_level(),
    quality_requirements: [String.t()],
    material_requirements: [String.t()]
  }

  @type t :: %__MODULE__{
    # Identification
    article_id: article_id(),
    article_name: String.t(),
    article_family: String.t(),
    sku: String.t(),

    # Spécifications techniques
    optimal_machine_type: machine_type(),
    compatible_machine_types: [machine_type()],
    optimal_pool_id: pool_id(),
    compatible_pool_ids: [pool_id()],

    # Caractéristiques de production
    complexity_level: complexity_level(),
    production_specs: production_spec(),

    # Contraintes et exigences
    min_batch_size: integer(),
    max_batch_size: integer(),
    requires_special_tooling: boolean(),
    tooling_change_time_seconds: integer(),

    # Qualité et certification
    quality_level: :standard | :high | :precision,
    certifications_required: [String.t()],
    inspection_points: [String.t()],

    # Coûts et pricing
    material_cost_per_unit: float(),
    target_production_cost: float(),
    selling_price: float(),
    margin_percent: float(),

    # Historique et performance
    avg_production_time_seconds: integer(),
    defect_rate_percent: float(),
    last_produced: DateTime.t() | nil,
    total_units_produced: integer(),

    # Métadonnées
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    is_active: boolean(),
    notes: String.t()
  }

  defstruct [
    :article_id,
    :article_name,
    :article_family,
    :sku,
    :optimal_machine_type,
    :compatible_machine_types,
    :optimal_pool_id,
    :compatible_pool_ids,
    :complexity_level,
    :production_specs,
    :min_batch_size,
    :max_batch_size,
    :requires_special_tooling,
    :tooling_change_time_seconds,
    :quality_level,
    :certifications_required,
    :inspection_points,
    :material_cost_per_unit,
    :target_production_cost,
    :selling_price,
    :margin_percent,
    :avg_production_time_seconds,
    :defect_rate_percent,
    :last_produced,
    :total_units_produced,
    :created_at,
    :updated_at,
    :is_active,
    :notes
  ]

  @doc """
  Crée un nouvel article avec les paramètres par défaut.
  """
  def new(article_id, article_name, article_family, optimal_machine_type, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      article_id: article_id,
      article_name: article_name,
      article_family: article_family,
      sku: Keyword.get(opts, :sku, article_id),
      optimal_machine_type: optimal_machine_type,
      compatible_machine_types: Keyword.get(opts, :compatible_machine_types, []),
      optimal_pool_id: Keyword.get(opts, :optimal_pool_id),
      compatible_pool_ids: Keyword.get(opts, :compatible_pool_ids, []),
      complexity_level: Keyword.get(opts, :complexity_level, :standard),
      production_specs: %{
        standard_duration_seconds: Keyword.get(opts, :standard_duration_seconds, 3600),
        setup_complexity: Keyword.get(opts, :setup_complexity, :standard),
        quality_requirements: Keyword.get(opts, :quality_requirements, []),
        material_requirements: Keyword.get(opts, :material_requirements, [])
      },
      min_batch_size: Keyword.get(opts, :min_batch_size, 1),
      max_batch_size: Keyword.get(opts, :max_batch_size, 1000),
      requires_special_tooling: Keyword.get(opts, :requires_special_tooling, false),
      tooling_change_time_seconds: Keyword.get(opts, :tooling_change_time_seconds, 0),
      quality_level: Keyword.get(opts, :quality_level, :standard),
      certifications_required: Keyword.get(opts, :certifications_required, []),
      inspection_points: Keyword.get(opts, :inspection_points, []),
      material_cost_per_unit: Keyword.get(opts, :material_cost_per_unit, 0.0),
      target_production_cost: Keyword.get(opts, :target_production_cost, 0.0),
      selling_price: Keyword.get(opts, :selling_price, 0.0),
      margin_percent: Keyword.get(opts, :margin_percent, 0.0),
      avg_production_time_seconds: Keyword.get(opts, :standard_duration_seconds, 3600),
      defect_rate_percent: Keyword.get(opts, :defect_rate_percent, 0.0),
      last_produced: nil,
      total_units_produced: 0,
      created_at: now,
      updated_at: now,
      is_active: true,
      notes: Keyword.get(opts, :notes, "")
    }
  end

  @doc """
  Met à jour les statistiques de production après fabrication.
  """
  def update_production_stats(article, units_produced, actual_time_seconds) do
    new_total = article.total_units_produced + units_produced

    # Calcul de la moyenne pondérée du temps de production
    current_total_time = article.avg_production_time_seconds * article.total_units_produced
    new_total_time = current_total_time + actual_time_seconds
    new_avg_time = if new_total > 0, do: round(new_total_time / new_total), else: 0

    %{article |
      total_units_produced: new_total,
      avg_production_time_seconds: new_avg_time,
      last_produced: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Calcule le temps de changement d'outils vers cet article.
  """
  def calculate_changeover_time(from_article, to_article) do
    cond do
      is_nil(from_article) -> 0
      from_article.article_id == to_article.article_id -> 0
      from_article.article_family == to_article.article_family ->
        min(from_article.tooling_change_time_seconds, to_article.tooling_change_time_seconds)
      true ->
        max(from_article.tooling_change_time_seconds, to_article.tooling_change_time_seconds)
    end
  end

  @doc """
  Vérifie la compatibilité avec un type de machine.
  """
  def compatible_with_machine_type?(article, machine_type) do
    article.optimal_machine_type == machine_type or
    machine_type in (article.compatible_machine_types || [])
  end

  @doc """
  Calcule le coût de production estimé.
  """
  def calculate_production_cost(article, machine_hourly_rate, quantity \\ 1) do
    production_hours = (article.avg_production_time_seconds * quantity) / 3600.0
    labor_cost = production_hours * machine_hourly_rate
    material_cost = article.material_cost_per_unit * quantity

    labor_cost + material_cost
  end

  @doc """
  Calcule la marge bénéficiaire.
  """
  def calculate_margin(article, production_cost) do
    if article.selling_price > 0 do
      margin = article.selling_price - production_cost - article.material_cost_per_unit
      margin_percent = (margin / article.selling_price) * 100.0
      {margin, margin_percent}
    else
      {0.0, 0.0}
    end
  end

  @doc """
  Sérialise l'article pour stockage ou transmission.
  """
  def serialize(article) do
    Map.take(article, [
      :article_id, :article_name, :article_family, :sku,
      :optimal_machine_type, :compatible_machine_types,
      :optimal_pool_id, :complexity_level,
      :min_batch_size, :max_batch_size,
      :quality_level, :material_cost_per_unit,
      :avg_production_time_seconds, :is_active
    ])
  end

  @doc """
  Valide la cohérence des données de l'article.
  """
  def validate(article) do
    errors = []

    errors = if is_nil(article.article_id) or article.article_id == "",
      do: ["article_id is required" | errors], else: errors

    errors = if article.min_batch_size < 1,
      do: ["min_batch_size must be positive" | errors], else: errors

    errors = if article.max_batch_size < article.min_batch_size,
      do: ["max_batch_size must be >= min_batch_size" | errors], else: errors

    errors = if article.avg_production_time_seconds < 0,
      do: ["avg_production_time_seconds must be non-negative" | errors], else: errors

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
