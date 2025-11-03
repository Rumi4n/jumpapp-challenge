import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :jumpapp_email_sorter, JumpappEmailSorter.Repo,
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  database: "jumpapp_email_sorter_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :jumpapp_email_sorter, JumpappEmailSorterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_purposes",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable Oban queues in test
config :jumpapp_email_sorter, Oban, testing: :manual

# Configure mocked dependencies for testing
config :jumpapp_email_sorter,
  gmail_client: JumpappEmailSorter.GmailClientMock,
  ai_service: JumpappEmailSorter.AIServiceMock

# Configure Wallaby for browser automation
# Note: Browser automation tests are excluded by default in test environment
# Run with: mix test --include browser
config :wallaby,
  driver: Wallaby.Chrome,
  hackney_options: [timeout: 30_000, recv_timeout: 30_000],
  screenshot_on_failure: false,
  js_errors: false,
  chrome: [
    headless: true,
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--disable-features=VizDisplayCompositor",
      "--window-size=1280,800"
    ]
  ]

# Exclude browser automation tests by default (ChromeDriver not always available)
ExUnit.configure(exclude: [browser: true])
