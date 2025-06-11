defmodule JSS.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      JSS.Repo,

      # PubSub system
      {Phoenix.PubSub, name: JSS.PubSub},

      # Phoenix Endpoint
      JSSWeb.Endpoint,

      # Core system actors
      JSS.System.ParameterManager,
      JSS.Actors.SwapEvaluator,
      JSS.Optimization.Coordinator
    ]

    opts = [strategy: :one_for_one, name: JSS.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Load default parameters on startup
        Task.start(fn ->
          Process.sleep(1000)
          JSS.System.ParameterManager.load_defaults()
        end)
        {:ok, pid}

      error -> error
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    JSSWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
