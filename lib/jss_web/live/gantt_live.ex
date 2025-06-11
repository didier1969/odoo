defmodule JSSWeb.GanttLive do
  use JSSWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Gantt Chart - JSS Scheduler")
     |> assign(:machines, get_demo_machines())
     |> assign(:zoom_level, "hours")}
  end

  def handle_event("change_zoom", %{"zoom" => zoom}, socket) do
    {:noreply, assign(socket, :zoom_level, zoom)}
  end

  def handle_event("start_optimization", _params, socket) do
    {:noreply, put_flash(socket, :info, "Optimization started")}
  end

  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <!-- Header -->
      <div class="bg-white border-b p-4">
        <div class="flex justify-between items-center">
          <h1 class="text-2xl font-bold">Gantt Chart</h1>

          <div class="flex space-x-4">
            <select phx-change="change_zoom" name="zoom" class="border rounded px-3 py-2">
              <option value="minutes" selected={@zoom_level == "minutes"}>Minutes</option>
              <option value="hours" selected={@zoom_level == "hours"}>Hours</option>
              <option value="days" selected={@zoom_level == "days"}>Days</option>
            </select>

            <button
              phx-click="start_optimization"
              class="bg-green-500 text-white px-4 py-2 rounded hover:bg-green-600"
            >
              Start Optimization
            </button>
          </div>
        </div>
      </div>

      <!-- Main content -->
      <div class="flex-1 flex">
        <!-- Machine sidebar -->
        <div class="w-64 bg-gray-50 border-r p-4">
          <h3 class="font-semibold mb-4">Machines</h3>
          <div class="space-y-2">
            <%= for machine <- @machines do %>
              <div class="bg-white border rounded p-3">
                <div class="font-medium"><%= machine.name %></div>
                <div class="text-sm text-gray-600"><%= machine.type %></div>
                <div class="text-xs">
                  <span class="inline-block w-2 h-2 rounded-full bg-green-400 mr-1"></span>
                  Available
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Gantt timeline -->
        <div class="flex-1 p-4">
          <div class="bg-white border rounded p-4">
            <h3 class="font-semibold mb-4">Timeline (Zoom: <%= @zoom_level %>)</h3>
            <div class="text-gray-500 text-center py-8">
              <p>Gantt chart visualization will appear here</p>
              <p class="text-sm">Start optimization to see tasks</p>
            </div>
          </div>
        </div>
      </div>

      <!-- Navigation -->
      <div class="bg-white border-t p-4">
        <div class="flex space-x-4">
          <.link navigate="/" class="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">
            Back to Dashboard
          </.link>
          <.link navigate="/admin" class="bg-purple-500 text-white px-4 py-2 rounded hover:bg-purple-600">
            Administration
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp get_demo_machines do
    [
      %{name: "Machine 1", type: "Type A"},
      %{name: "Machine 2", type: "Type B"},
      %{name: "Machine 3", type: "Type A"},
      %{name: "Machine 4", type: "Type C"},
      %{name: "Machine 5", type: "Type B"}
    ]
  end
end
