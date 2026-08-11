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

  # Rows ready for the breakdown view. `detail` is the human number behind the
  # ratio, read from the extractor - the evaluator normalises to 0..1 and loses
  # the unit, so it cannot be the source of the detail.
  # @param evaluation [Hash] the component ratios from the health evaluator.
  # @param extractor [Object] the table extractor providing the detail numbers.
  # @return [Array<Hash>] one hash per component with label, ratio, and severity.
  def health_component_rows(evaluation, extractor)
    evaluation.fetch(:components, {}).map do |key, ratio|
      meta = COMPONENT_META.fetch(key)
      {
        label: t("health.component_labels.#{key}"),
        explains: t("health.component_explains.#{key}"),
        operation: meta[:operation],
        ratio: ratio,
        has_data: !ratio.nil?,
        pct: ratio.nil? ? nil : (ratio * 100).round,
        severity: severity_for(ratio),
        detail: component_detail(key, extractor)
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

  # Builds the human-readable detail string for a component from extractor
  # numbers, or nil when the detail is not available.
  # @param key [Symbol] the component, e.g. :fragmentation or :delete_overhead.
  # @param extractor [Object] the table extractor providing the underlying numbers.
  # @return [String, nil] the translated detail, or nil when unavailable.
  def component_detail(key, extractor)
    case key
    when :fragmentation
      avg = extractor.average_file_size
      return nil if avg.nil?

      target = (extractor.properties["write.target-file-size-bytes"] || 128 * 1024 * 1024).to_i
      t("health.detail_fragmentation",
        avg: number_to_human_size(avg), target: number_to_human_size(target))
    when :snapshot_buildup
      count = extractor.snapshot_count
      count.nil? ? nil : t("health.detail_snapshots", count: count)
    when :delete_overhead
      records = extractor.total_records
      deletes = [ extractor.position_deletes, extractor.equality_deletes ].compact.sum
      return nil if records.nil? || records.zero?

      t("health.detail_deletes",
        deletes: number_with_delimiter(deletes), records: number_with_delimiter(records))
    when :manifest_buildup
      nil
    end
  end
end
