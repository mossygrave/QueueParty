defmodule QueueParty.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QueuePartyWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:queue_party, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: QueueParty.PubSub},
      QueueParty.Rooms,
      {Task.Supervisor, name: QueueParty.TitleTasks, max_children: 32},
      # Start a worker by calling: QueueParty.Worker.start_link(arg)
      # {QueueParty.Worker, arg},
      # Start to serve requests, typically the last entry
      QueuePartyWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QueueParty.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QueuePartyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
