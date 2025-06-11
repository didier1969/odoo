defmodule JSSWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JSSWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JSSWeb do
    pipe_through :browser

    # Page d'accueil avec dashboard principal
    live "/", DashboardLive, :index

    # Gantt Chart principal
    live "/gantt", GanttLive, :index

    # Administration des paramètres
    live "/admin", AdminLive, :index
    live "/admin/parameters", AdminLive, :parameters
    live "/admin/performance", AdminLive, :performance

    # Monitoring système
    live "/monitoring", MonitoringLive, :index
    live "/monitoring/algorithms", MonitoringLive, :algorithms
    live "/monitoring/statistics", MonitoringLive, :statistics

    # Gestion des données
    live "/data", DataLive, :index
    live "/data/machines", DataLive, :machines
    live "/data/orders", DataLive, :orders
    live "/data/tasks", DataLive, :tasks
  end

  # API endpoints
  scope "/api", JSSWeb do
    pipe_through :api

    get "/status", ApiController, :status
    get "/metrics", ApiController, :metrics
    post "/optimization/start", ApiController, :start_optimization
    post "/optimization/stop", ApiController, :stop_optimization
    get "/optimization/status", ApiController, :optimization_status
  end

  # Phoenix LiveDashboard (monitoring)
  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser
    live_dashboard "/dashboard",
      metrics: JSSWeb.Telemetry,
      additional_pages: []
  end

  # Helper functions
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
end
