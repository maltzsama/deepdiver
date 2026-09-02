# View helpers that render the table health breakdown view, mapping evaluator
# ratios to labels, operations, and severity styling.
module HealthHelper
  # Which maintenance operation fixes each component. Labels and explanations
  # live in the locale, so the UI language stays with the rest of the app.
  COMPONENT_META = {
    fragmentation:    { operation: "optimize" },
    snapshot_buildup: { operation: "expire_snapshots" },
    delete_overhead:  { operation: "optimize" },
    manifest_buildup: { operation: "optimize_manifests" }
  }.freeze

  # Rows ready for the breakdown view.
  #
  # `detail` is the human number behind the ratio, read from the evaluation's
  # own `details` - the evaluator normalises to 0..1 and loses the unit, so it
  # emits the measured values alongside. Taking them from the evaluation rather
  # than from a separately-built extractor keeps the panel describing ONE
  # evaluation, which is what makes a persisted read and a fresh evaluation
  # render identically (see #215).
  #
  # Every row has the same shape whether or not it has data, so the view can
  # render an identical structure per row and the columns line up (see #219).
  #
  # @param evaluation [Hash] the health evaluator result (persisted or fresh).
  # @return [Array<Hash>] one hash per component with label, ratio, and severity.
  def health_component_rows(evaluation)
    details = evaluation[:details] || {}

    evaluation.fetch(:components, {}).map do |key, ratio|
      meta = COMPONENT_META.fetch(key)
      {
        label: t("health.component_labels.#{key}"),
        explains: t("health.component_explains.#{key}"),
        operation: meta[:operation],
        ratio: ratio,
        has_data: !ratio.nil?,
        # A row with no data still reports 0 so the view can render the track
        # at a fixed width with an empty fill, instead of a shorter row.
        pct: ratio.nil? ? 0 : (ratio * 100).round,
        severity: severity_for(ratio),
        detail: component_detail(key, details)
      }
    end
  end

  # Maps a severity to the background colour class used for its bar.
  # @param severity [Symbol] the severity, one of :ok, :warning, or :critical.
  # @return [String] the background CSS class for the severity.
  def severity_fill_class(severity)
    case severity
    when :ok       then "bg-ok-DEFAULT"
    when :warning  then "bg-warn-DEFAULT"
    when :critical then "bg-red-DEFAULT"
    else "bg-cosmos-line"
    end
  end

  private

  # High ratio = healthy (1.0 is great). The bar shows how much is left; the
  # colour warns when it is low.
  # @param ratio [Float, nil] the component ratio in 0..1, or nil when unknown.
  # @return [Symbol] :ok, :warning, :critical, or :none when the ratio is nil.
  def severity_for(ratio)
    return :none if ratio.nil?
    return :critical if ratio < 0.4
    return :warning if ratio < 0.7

    :ok
  end

  # Builds the human-readable detail string for a component from the measured
  # values the evaluator emitted, or nil when the numbers are not available.
  #
  # Every component has a detail, including manifests - it used to return nil
  # unconditionally, so the Manifests row rendered a filled bar and a bare
  # arrow with no number explaining it while every sibling showed "X over Y".
  #
  # @param key [Symbol] the component, e.g. :fragmentation or :delete_overhead.
  # @param details [Hash] the measured values from the evaluation.
  # @return [String, nil] the translated detail, or nil when unavailable.
  def component_detail(key, details)
    case key
    when :fragmentation   then detail_fragmentation(details)
    when :snapshot_buildup then detail_budgeted(details, :snapshot_count, :snapshot_budget, "health.detail_snapshots")
    when :delete_overhead then detail_deletes(details)
    when :manifest_buildup then detail_budgeted(details, :manifest_count, :manifest_budget, "health.detail_manifests")
    end
  end

  # "avg 61 KB of 128 MB target".
  def detail_fragmentation(details)
    avg = details[:average_file_size]
    return nil if avg.nil?

    target = (details[:target_file_size] || 128 * 1024 * 1024).to_i
    t("health.detail_fragmentation",
      avg: number_to_human_size(avg), target: number_to_human_size(target))
  end

  # "182 of 40 retained" — a count against the budget it is measured against.
  def detail_budgeted(details, count_key, budget_key, scope)
    count = details[count_key]
    budget = details[budget_key]
    return nil if count.nil? || budget.nil?

    t(scope, count: number_with_delimiter(count), budget: number_with_delimiter(budget))
  end

  # "12 deletes over 1,000,000 records".
  def detail_deletes(details)
    records = details[:total_records]
    deletes = details[:delete_count]
    return nil if records.nil? || records.zero? || deletes.nil?

    t("health.detail_deletes",
      deletes: number_with_delimiter(deletes), records: number_with_delimiter(records))
  end
end
