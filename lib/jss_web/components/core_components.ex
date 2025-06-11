defmodule JSSWeb.CoreComponents do
  use Phoenix.Component

  @doc """
  Renders flash notices.
  """
  attr :flash, :map, default: %{}
  attr :kind, :atom, values: [:info, :error, :warn, :success]

  def flash(assigns) do
    ~H"""
    <div
      :if={Phoenix.Flash.get(@flash, @kind)}
      class={[
        "fixed top-4 right-4 px-4 py-2 rounded shadow-lg z-50",
        @kind == :info && "bg-blue-100 text-blue-800",
        @kind == :error && "bg-red-100 text-red-800",
        @kind == :warn && "bg-yellow-100 text-yellow-800",
        @kind == :success && "bg-green-100 text-green-800"
      ]}
      role="alert"
    >
      <%= Phoenix.Flash.get(@flash, @kind) %>
    </div>
    """
  end

  @doc """
  Shows the flash group.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:warn} flash={@flash} />
      <.flash kind={:success} flash={@flash} />
    </div>
    """
  end

  def translate_error({msg, _opts}) do
    msg
  end

  def translate_error(msg) do
    msg
  end
end
