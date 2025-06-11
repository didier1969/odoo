import Config
config :logger, level: :debug


# Configuration esbuild et tailwind
config :esbuild, :version, "0.25.0"
config :tailwind, :version, "3.4.6"

# Configuration Phoenix Endpoint
config :jss, JSSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "super_secret_key_for_dev_jss_scheduler_application_this_is_long_enough_for_64_bytes_minimum_requirement_phoenix_elixir"


# Configuration esbuild et tailwind
config :esbuild, :version, "0.25.0"
config :tailwind, :version, "3.4.6"

# Configuration Phoenix Endpoint
config :jss, JSSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "super_secret_key_for_dev_jss_scheduler_application_this_is_long_enough_for_64_bytes_minimum_requirement_phoenix_elixir"


# Configuration LiveView signing salt
config :jss, JSSWeb.Endpoint,
  live_view: [signing_salt: "GEeysnaQUMBt6QBC"]

# Configuration Phoenix LiveView
config :jss, JSSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "VGhpcyBpcyBhIGZha2Ugc2VjcmV0IGtleSBmb3IgZGV2ZWxvcG1lbnQgb25seSEhISEhIQ==",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading
config :jss, JSSWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/jss_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Configure esbuild
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind
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