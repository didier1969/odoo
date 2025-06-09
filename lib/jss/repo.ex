defmodule JSS.Repo do
  use Ecto.Repo,
    otp_app: :jss,
    adapter: Ecto.Adapters.Postgres
end
