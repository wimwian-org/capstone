defmodule NewWebApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NewWebAppWeb.Telemetry,
      NewWebApp.Repo,
      {DNSCluster, query: Application.get_env(:new_web_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NewWebApp.PubSub},
      # Start a worker by calling: NewWebApp.Worker.start_link(arg)
      # {NewWebApp.Worker, arg},
      # Start to serve requests, typically the last entry
      NewWebAppWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NewWebApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NewWebAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
