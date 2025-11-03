# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :jumpapp_email_sorter,
  ecto_repos: [JumpappEmailSorter.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :jumpapp_email_sorter, JumpappEmailSorterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: JumpappEmailSorterWeb.ErrorHTML, json: JumpappEmailSorterWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JumpappEmailSorter.PubSub,
  live_view: [signing_salt: "5axW+f9K"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :jumpapp_email_sorter, JumpappEmailSorter.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  jumpapp_email_sorter: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  jumpapp_email_sorter: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "email profile https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly",
         access_type: "offline",
         prompt: "consent"
       ]}
  ]

# OAuth credentials are configured in runtime.exs

# Configure Oban
config :jumpapp_email_sorter, Oban,
  repo: JumpappEmailSorter.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Poll for new emails every 1 minute
       {"* * * * *", JumpappEmailSorter.Workers.GmailPollWorker}
     ]}
  ],
  queues: [default: 10, email_import: 5, unsubscribe: [limit: 1, paused: false]]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
