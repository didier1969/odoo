# config/database.exs
import Config

config :jss, JSS.Repo,
  adapter: Ecto.Adapters.Postgres,
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASS") || "stdi5757?",
  show_sensitive_data_on_connection_error: true