defmodule JSSWeb.DataLive do
  use JSSWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Data Management")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold mb-4">Data Management</h1>
      <p>Data management interface coming soon...</p>
    </div>
    """
  end
end
