import Config

# Configuration Ecto
config :jss, ecto_repos: [JSS.Repo]

# Configuration base de données
config :jss, JSS.Repo,
  username: "postgres",
  password: "stdi5757?",
  hostname: "localhost",
  database: "jss_dev",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

# Configuration Phoenix Endpoint
config :jss, JSSWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: JSSWeb.ErrorHTML, json: JSSWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JSS.PubSub,
  live_view: [signing_salt: "jss_live_view_salt"],
  secret_key_base: "super_secret_key_base_for_dev_environment_jss_scheduler_very_long_string_that_must_be_at_least_64_bytes"

# Configuration Phoenix
config :phoenix, :json_library, Jason

# Configuration Gettext
config :jss, JSSWeb.Gettext,
  default_locale: "en",
  locales: ~w(en fr)

# Configuration Telemetry
config :jss, :telemetry, [
  {JSSWeb.Telemetry, []}
]

# Configuration Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configuration esbuild
config :esbuild,
  version: "0.17.11",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configuration tailwind
config :tailwind,
  version: "3.3.0",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"

# Import default parameters
import_config "default_parameters.exs"
