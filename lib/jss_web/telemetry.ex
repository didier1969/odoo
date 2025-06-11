defmodule JSSWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_join.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("jss.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("jss.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("jss.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("jss.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("jss.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # JSS Custom Metrics
      last_value("jss.optimization.current_score"),
      counter("jss.optimization.iterations_total"),
      summary("jss.optimization.algorithm_duration",
        tags: [:algorithm],
        unit: {:native, :millisecond}
      ),
      last_value("jss.system.active_machines"),
      last_value("jss.system.active_orders"),
      last_value("jss.system.active_tasks")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      {__MODULE__, :dispatch_vm_metrics, []},
      {__MODULE__, :dispatch_jss_metrics, []}
    ]
  end

  def dispatch_vm_metrics do
    :telemetry.execute([:vm, :memory], :erlang.memory())
    :telemetry.execute([:vm, :total_run_queue_lengths], :erlang.statistics(:total_run_queue_lengths))
  end

  def dispatch_jss_metrics do
    try do
      # Métriques du coordinateur
      status = JSS.Optimization.Coordinator.get_status()
      :telemetry.execute([:jss, :optimization], %{
        current_score: status[:current_score] || 0,
        cycle_number: status[:cycle_number] || 0
      })

      # Métriques système
      :telemetry.execute([:jss, :system], %{
        active_machines: count_active_entities(:machines),
        active_orders: count_active_entities(:orders),
        active_tasks: count_active_entities(:tasks)
      })
    rescue
      _ -> :ok  # Ignore errors during metrics collection
    end
  end

  defp count_active_entities(_type) do
    # Placeholder - à implémenter selon vos besoins
    0
  end
end
