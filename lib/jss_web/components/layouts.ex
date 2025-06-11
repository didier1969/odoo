defmodule JSSWeb.Layouts do
  use JSSWeb, :html
  import Phoenix.Controller, only: [get_csrf_token: 0]
  embed_templates "layouts/*"
end
