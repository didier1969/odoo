defmodule JSSWeb.ApiController do
  use Phoenix.Controller, formats: [:json]

  def status(conn, _params) do
    status_data = %{
      coordinator: get_coordinator_status(),
      timestamp: DateTime.utc_now()
    }
    json(conn, %{status: "ok", data: status_data})
  end

  def metrics(conn, _params) do
    metrics_data = %{
      system: get_system_metrics(),
      timestamp: DateTime.utc_now()
    }
    json(conn, %{status: "ok", data: metrics_data})
  end

  defp get_coordinator_status do
    try do
      JSS.Optimization.Coordinator.get_status()
    rescue
      _ -> %{status: :unavailable}
    end
  end

  defp get_system_metrics do
    %{
      memory: :erlang.memory(),
      process_count: length(Process.list()),
      uptime: System.system_time(:second)
    }
  end
end