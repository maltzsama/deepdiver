# Prometheus metrics. The web pod exposes them on GET /metrics (scraped by a
# cluster-side PodMonitor); see docs/helm-remediation.md.
require "prometheus/client"
require "prometheus/client/formats/text"
#
# The application runs several processes (web + three Solid Queue workers) and
# only the web pod is scraped, so anything a worker would increment in-process
# would be invisible. Application metrics are therefore DERIVED FROM THE
# DATABASE at scrape time (a gauge refreshed on every request), which stays
# correct regardless of which pod does the work. Service metrics (HTTP, SQL,
# process) only make sense on the web pod and are enabled explicitly with
# PROMETHEUS_SERVICE_METRICS=1.
module PrometheusMetrics
  REGISTRY = Prometheus::Client::Registry.new

  # --- Application metrics (always on, DB-derived) ---

  EXECUTION_STATUS = Prometheus::Client::Gauge.new(
    :deepdiver_execution_status,
    docstring: "Number of maintenance executions currently in each status",
    labels: [ :status ]
  )

  TRINO_ENGINE_STATUS = Prometheus::Client::Gauge.new(
    :deepdiver_trino_engine_status,
    docstring: "1 when the Trino engine is in the given lifecycle state, otherwise 0",
    labels: [ :status ]
  )

  ERROR_EVENTS = Prometheus::Client::Gauge.new(
    :deepdiver_error_events,
    docstring: "Number of error events currently in each status",
    labels: [ :status ]
  )

  SOLID_QUEUE_JOBS = Prometheus::Client::Gauge.new(
    :deepdiver_solid_queue_jobs,
    docstring: "Number of Solid Queue jobs by queue and lifecycle state",
    labels: [ :queue_name, :state ]
  )

  # --- Service metrics (opt-in, web pod only) ---

  HTTP_REQUESTS_TOTAL = Prometheus::Client::Counter.new(
    :deepdiver_http_requests_total,
    docstring: "HTTP requests handled, by method and status code",
    labels: [ :method, :status ]
  )

  HTTP_REQUEST_DURATION = Prometheus::Client::Histogram.new(
    :deepdiver_http_request_duration_seconds,
    docstring: "HTTP request duration in seconds"
  )

  SQL_QUERIES_TOTAL = Prometheus::Client::Counter.new(
    :deepdiver_sql_queries_total,
    docstring: "SQL queries executed"
  )

  SQL_QUERY_DURATION = Prometheus::Client::Histogram.new(
    :deepdiver_sql_query_duration_seconds,
    docstring: "SQL query duration in seconds"
  )

  PROCESS_CPU_SECONDS = Prometheus::Client::Gauge.new(
    :deepdiver_process_cpu_seconds,
    docstring: "Total user and system CPU time consumed by the process"
  )

  PROCESS_RESIDENT_MEMORY = Prometheus::Client::Gauge.new(
    :deepdiver_process_resident_memory_bytes,
    docstring: "Resident memory size of the process in bytes"
  )

  APP_METRICS = [
    EXECUTION_STATUS, TRINO_ENGINE_STATUS, ERROR_EVENTS, SOLID_QUEUE_JOBS
  ].freeze

  SERVICE_METRICS = [
    HTTP_REQUESTS_TOTAL, HTTP_REQUEST_DURATION, SQL_QUERIES_TOTAL,
    SQL_QUERY_DURATION, PROCESS_CPU_SECONDS, PROCESS_RESIDENT_MEMORY
  ].freeze

  class << self
    # Whether service metrics (HTTP/SQL/process) are enabled. App metrics are
    # always on.
    def service_metrics_enabled? = ENV["PROMETHEUS_SERVICE_METRICS"] == "1"

    # Registers the always-on metrics and, when enabled, the service metrics and
    # their ActiveSupport::Notifications subscriptions. Called once at boot.
    def setup!
      APP_METRICS.each { |metric| REGISTRY.register(metric) }
      return unless service_metrics_enabled?

      SERVICE_METRICS.each { |metric| REGISTRY.register(metric) }
      subscribe_to_instrumentation!
    end

    # Refreshes every DB-derived gauge from the current database state. Called
    # by MetricsController on each scrape so values never drift. Never raises:
    # a metrics scrape must not take down the app.
    def refresh!
      refresh_execution_status!
      refresh_trino_engine_status!
      refresh_error_events!
      refresh_solid_queue!
      refresh_process_metrics!
    rescue StandardError => e
      Rails.logger.warn("PrometheusMetrics.refresh! failed: #{e.message}")
    end

    # Renders the registry in the Prometheus text exposition format.
    def to_text = Prometheus::Client::Formats::Text.marshal(REGISTRY)

    private

    def refresh_execution_status!
      ExecutionHistory.group(:status).count.each do |status, count|
        EXECUTION_STATUS.set(count, labels: { status: status })
      end
    end

    def refresh_trino_engine_status!
      state = TrinoEngineState.first
      TrinoEngineState::STATUSES.each do |status|
        TRINO_ENGINE_STATUS.set(state&.status == status ? 1 : 0, labels: { status: status })
      end
    end

    def refresh_error_events!
      ErrorEvent.group(:status).count.each do |status, count|
        ERROR_EVENTS.set(count, labels: { status: status })
      end
    end

    def refresh_solid_queue!
      {
        "ready" => SolidQueue::ReadyExecution,
        "running" => SolidQueue::ClaimedExecution,
        "blocked" => SolidQueue::BlockedExecution,
        "scheduled" => SolidQueue::ScheduledExecution,
        "failed" => SolidQueue::FailedExecution
      }.each do |state, model|
        model.group(:queue_name).count.each do |queue_name, count|
          SOLID_QUEUE_JOBS.set(count, labels: { queue_name: queue_name, state: state })
        end
      end
    end

    def refresh_process_metrics!
      return unless service_metrics_enabled?

      PROCESS_CPU_SECONDS.set(cpu_seconds)
      PROCESS_RESIDENT_MEMORY.set(resident_memory_bytes)
    end

    def cpu_seconds
      times = Process.times
      times.utime + times.stime
    end

    def resident_memory_bytes
      status = File.read("/proc/self/status")
      vmrss = status[/^VmRSS:\s+(\d+)\s+kB/, 1]
      vmrss ? vmrss.to_i * 1024 : 0
    rescue StandardError
      0
    end

    def subscribe_to_instrumentation!
      ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        payload = event.payload
        HTTP_REQUESTS_TOTAL.increment(labels: { method: payload[:method].to_s, status: payload[:status].to_s })
        HTTP_REQUEST_DURATION.observe(event.duration / 1000.0)
      end

      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        SQL_QUERIES_TOTAL.increment
        SQL_QUERY_DURATION.observe(event.duration / 1000.0)
      end
    end
  end
end

PrometheusMetrics.setup!
