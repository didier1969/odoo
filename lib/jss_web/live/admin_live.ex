defmodule JSSWeb.AdminLive do
  use JSSWeb, :live_view
  require Logger

  alias JSS.System.ParameterManager

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Administration - JSS Scheduler")
     |> assign(:parameters, get_all_parameters())}
  end

  def handle_event("refresh_cache", _params, socket) do
    ParameterManager.refresh_cache()
    {:noreply, put_flash(socket, :success, "Cache refreshed")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold text-gray-900 mb-6">System Administration</h1>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Parameters -->
        <div class="bg-white rounded-lg shadow p-6">
          <h3 class="text-lg font-semibold mb-4">System Parameters</h3>
          <div class="space-y-2">
            <%= for {category, params} <- @parameters do %>
              <div class="border-b pb-2">
                <h4 class="font-medium text-gray-900"><%= String.capitalize(category) %></h4>
                <p class="text-sm text-gray-600"><%= map_size(params) %> parameters</p>
              </div>
            <% end %>
          </div>

          <button
            phx-click="refresh_cache"
            class="mt-4 bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600"
          >
            Refresh Cache
          </button>
        </div>

        <!-- System Info -->
        <div class="bg-white rounded-lg shadow p-6">
          <h3 class="text-lg font-semibold mb-4">System Information</h3>
          <div class="space-y-2">
            <div class="flex justify-between">
              <span>Memory:</span>
              <span>45.2 MB</span>
            </div>
            <div class="flex justify-between">
              <span>Processes:</span>
              <span>156</span>
            </div>
            <div class="flex justify-between">
              <span>Uptime:</span>
              <span>2h 15m</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Navigation -->
      <div class="mt-8 flex space-x-4">
        <.link navigate="/" class="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">
          Back to Dashboard
        </.link>
        <.link navigate="/gantt" class="bg-indigo-500 text-white px-4 py-2 rounded hover:bg-indigo-600">
          View Gantt Chart
        </.link>
      </div>
    </div>
    """
  end

  defp get_all_parameters do
    %{
      "optimizer" => %{"delay_weight" => 1.0, "advance_weight" => 0.5},
      "system" => %{"snapshot_interval" => 300, "debug_mode" => false},
      "demo" => %{"machine_count" => 100, "order_count" => 500}
    }
  end
end
