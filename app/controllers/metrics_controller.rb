# Exposes Prometheus metrics in the text exposition format on GET /metrics.
#
# Deliberately a bare ActionController::Metal rather than ApplicationController:
# the latter forces authentication, Pundit and browser checks. Metrics are read
# directly by the Prometheus PodMonitor inside the cluster, which cannot
# authenticate. Metal also skips ActionController instrumentation, so the
# periodic scrape does not pollute the HTTP request metrics.
class MetricsController < ActionController::Metal
  def index
    PrometheusMetrics.refresh!
    self.content_type = "text/plain; version=0.0.4"
    self.response_body = PrometheusMetrics.to_text
  end
end
