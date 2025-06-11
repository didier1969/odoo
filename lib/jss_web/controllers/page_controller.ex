defmodule JSSWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  def favicon(conn, _params) do
    send_resp(conn, 404, "Not found")
  end
end