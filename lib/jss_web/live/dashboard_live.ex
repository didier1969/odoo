defmodule JSSWeb.DashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
    end

    {:ok, assign(socket,
      coordinator_status: get_coordinator_status(),
      last_update: DateTime.utc_now(),
      test_running: false
    )}
  end

  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign(socket,
      coordinator_status: get_coordinator_status(),
      last_update: DateTime.utc_now()
    )}
  end

  def handle_event("run_test", _params, socket) do
    spawn(fn ->
      # ✅ CORRECTION: Suppression du module dupliqué
      JSS.Test.OptimizationPipelineTest.run_simple_test(
        machine_count: 5,
        order_count: 8,
        algorithm_timeout: 3000
      )
    end)
    {:noreply, put_flash(socket, :info, "Test started")}
  end

  def render(assigns) do
    ~H"""
    <div class="card">
      <h1>JSS Scheduler Dashboard</h1>
      <p>Last update: <%= Calendar.strftime(@last_update, "%H:%M:%S") %></p>

      <div class="card">
        <h2>System Status</h2>
        <p class={if @coordinator_status.coordinator_status == :running, do: "status-running", else: "status-idle"}>
          Coordinator: <%= @coordinator_status.coordinator_status %>
        </p>
        <p>Algorithm: <%= @coordinator_status.current_algorithm || "None" %></p>
        <p>Cycle: <%= @coordinator_status.cycle_number || 0 %></p>
      </div>

      <div class="card">
        <h2>Quick Actions</h2>
        <button phx-click="run_test" class="btn" disabled={@test_running}>
          <%= if @test_running, do: "Test Running...", else: "Run Test Pipeline" %>
        </button>

        <div class="mt-4">
          <.link navigate="/gantt" class="btn bg-indigo-500 hover:bg-indigo-600">
            View Gantt Chart
          </.link>

          <.link navigate="/admin" class="btn bg-purple-500 hover:bg-purple-600 ml-2">
            Administration
          </.link>
        </div>
      </div>

      <div class="card">
        <h2>System Metrics</h2>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <span class="text-gray-600">Memory Usage:</span>
            <span class="font-semibold"><%= format_memory() %></span>
          </div>
          <div>
            <span class="text-gray-600">Process Count:</span>
            <span class="font-semibold"><%= length(Process.list()) %></span>
          </div>
          <div>
            <span class="text-gray-600">Uptime:</span>
            <span class="font-semibold"><%= format_uptime() %></span>
          </div>
          <div>
            <span class="text-gray-600">Parameters:</span>
            <span class="font-semibold"><%= get_parameter_count() %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, 2000)
  end

  defp get_coordinator_status do
    try do
      JSS.Optimization.Coordinator.get_status()
    rescue
      _ -> %{coordinator_status: :idle, current_algorithm: nil, cycle_number: 0}
    end
  end

  defp format_memory do
    memory = :erlang.memory(:total)
    "#{Float.round(memory / 1_048_576, 1)} MB"
  end

  defp format_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    hours = div(uptime_ms, 3_600_000)
    minutes = div(rem(uptime_ms, 3_600_000), 60_000)
    "#{hours}h #{minutes}m"
  end

  defp get_parameter_count do
    try do
      JSS.Repo.aggregate(JSS.Schemas.SystemParameter, :count, :id)
    rescue
      _ -> "N/A"
    end
  end
end
