defmodule JumpappEmailSorter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JumpappEmailSorterWeb.Telemetry,
      JumpappEmailSorter.Repo,
      {DNSCluster, query: Application.get_env(:jumpapp_email_sorter, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JumpappEmailSorter.PubSub},
      # Start Oban
      {Oban, Application.fetch_env!(:jumpapp_email_sorter, Oban)},
      # Start a worker by calling: JumpappEmailSorter.Worker.start_link(arg)
      # {JumpappEmailSorter.Worker, arg},
      # Start to serve requests, typically the last entry
      JumpappEmailSorterWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JumpappEmailSorter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JumpappEmailSorterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
