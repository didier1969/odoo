# config/default_parameters.exs
# Configuration des paramètres par défaut pour JSS

config :jss, :default_parameters, %{
  # Paramètres d'optimisation
  optimizer: %{
    # Poids de la fonction de coût
    delay_weight: 1.0,
    advance_weight: 0.5,
    setup_weight: 2.0,
    hierarchy_flat_rate: 100.0,

    # Timeouts des algorithmes (millisecondes)
    algorithm_time_budget: 30_000,
    simulated_annealing_timeout: 30_000,
    vns_timeout: 30_000,
    hybrid_timeout: 30_000,

    # Paramètres Simulated Annealing
    sa_initial_temperature: 1000.0,
    sa_cooling_rate: 0.95,
    sa_min_temperature: 0.01,
    sa_swap_probability: 0.7,
    sa_reassignment_probability: 0.3,

    # Paramètres VNS
    vns_max_neighborhoods: 3,
    vns_local_search_iterations: 100,
    vns_no_improvement_threshold: 50,

    # Paramètres Hybrid
    hybrid_phase_switch_threshold: 50,
    hybrid_convergence_window: 10,
    hybrid_convergence_threshold: 0.01,

    # SwapEvaluator
    swap_evaluation_timeout: 5000,
    swap_cache_size: 1000,
    swap_cache_ttl: 30000,

    # Négociation
    negotiation_enabled: true,
    negotiation_batch_size: 50,
    negotiation_timeout: 3000,

    # Fréquence de visite des tâches critiques
    critical_task_visit_multiplier: 2.0
  },

  # Paramètres système
  system: %{
    # Intervalles de sauvegarde (millisecondes)
    snapshot_full_interval: 300_000,      # 5 minutes
    snapshot_partial_interval: 60_000,    # 1 minute
    snapshot_retention_days: 30,

    # Mise à jour temps réel
    optimization_interval: 1000,          # 1 seconde
    websocket_push_interval: 2000,        # 2 secondes
    parameter_cache_refresh_interval: 30_000, # 30 secondes

    # Performance
    max_concurrent_evaluations: 10,
    actor_supervisor_max_restarts: 5,
    actor_supervisor_max_seconds: 60,

    # Gestion temporelle
    planning_horizon_days: 90,
    immutable_horizon_days: 30,
    virtual_progress_enabled: true,

    # Événements externes
    external_event_buffer_size: 1000,
    operator_feedback_timeout: 10000,

    # Logging et monitoring
    performance_metrics_enabled: true,
    algorithm_statistics_retention: 100,
    debug_mode: false
  },

  # Paramètres de génération de données de démonstration
  demo: %{
    # Volumes
    demo_machine_count: 100,
    demo_order_count: 500,
    demo_article_count: 50,
    demo_pool_count: 10,
    demo_task_count_per_order_min: 1,
    demo_task_count_per_order_max: 10,

    # Durées (secondes)
    demo_task_duration_min: 1800,         # 30 minutes
    demo_task_duration_max: 28800,        # 8 heures
    demo_setup_time_min: 300,             # 5 minutes
    demo_setup_time_max: 7200,            # 2 heures

    # Calendriers machines (heures par jour)
    demo_machine_capacity_min: 8.0,
    demo_machine_capacity_max: 24.0,

    # Pourcentages
    demo_parallel_machine_ratio: 0.2,     # 20% de machines parallèles
    demo_urgent_order_ratio: 0.1,         # 10% de commandes urgentes

    # Coûts (CHF)
    demo_technology_rate_min: 50.0,
    demo_technology_rate_max: 200.0,

    # Horizons temporels
    demo_delivery_date_min_days: 7,
    demo_delivery_date_max_days: 60,

    # Données de test reproductibles
    demo_random_seed: 42,
    demo_auto_generate_on_startup: true
  },

  # Paramètres d'interface utilisateur
  ui: %{
    # Gantt Chart
    gantt_time_scale_default: "hours",     # "minutes", "hours", "days"
    gantt_zoom_levels: ["minutes", "hours", "days", "weeks"],
    gantt_max_visible_machines: 50,
    gantt_auto_refresh_enabled: true,
    gantt_show_setup_times: true,
    gantt_show_task_details: true,

    # Filtres par défaut
    filter_default_time_range_days: 7,
    filter_default_machine_types: [],     # Empty = all types
    filter_default_order_priorities: [],  # Empty = all priorities
    filter_show_completed_tasks: false,

    # Couleurs et styles
    gantt_color_scheme: "default",         # "default", "colorblind", "dark"
    gantt_task_height: 30,
    gantt_machine_row_height: 40,

    # Performance UI
    ui_pagination_size: 50,
    ui_search_debounce_ms: 300,
    ui_auto_save_interval: 5000,

    # Notifications
    ui_show_notifications: true,
    ui_notification_duration: 5000,
    ui_sound_enabled: false,

    # Admin interface
    admin_parameter_categories_expanded: true,
    admin_show_advanced_settings: false,
    admin_auto_apply_changes: false,

    # Responsive breakpoints
    ui_mobile_breakpoint: 768,
    ui_tablet_breakpoint: 1024,
    ui_desktop_breakpoint: 1200
  }
}
