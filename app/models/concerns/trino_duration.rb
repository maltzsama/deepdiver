# Parsing and comparison for the Trino duration strings the app both sends to
# the engine (a step's `retention_threshold`) and configures on it (the
# connector's `min-retention` floors).
#
# The two are compared at validation time so a step whose retention is below
# the configured floor is rejected on save, naming the floor, instead of
# failing mid-chain hours later with Trino's own error.
module TrinoDuration
  # A duration/threshold magnitude plus a unit, e.g. "7d", "128MB", "1.5GB".
  # These are interpolated straight into the ALTER TABLE ... EXECUTE statement,
  # so anything else is rejected instead of shipped as raw SQL.
  PATTERN = /\A\d+(?:\.\d+)?\s*[a-zA-Z]+\z/

  # Trino's duration units, in seconds. Matches io.airlift.units.Duration.
  UNITS = {
    "ns" => 1e-9, "us" => 1e-6, "ms" => 1e-3,
    "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400
  }.freeze

  module_function

  # Whether a value is a well-formed magnitude plus unit.
  #
  # @param value [Object] the value to check
  # @return [Boolean]
  def well_formed?(value)
    value.to_s.match?(PATTERN)
  end

  # The duration in seconds, or nil when the value is not a parseable TIME
  # duration (a size like "128MB" is well formed but has no time unit).
  #
  # @param value [Object] the duration string
  # @return [Float, nil] seconds
  def to_seconds(value)
    match = value.to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*([a-zA-Z]+)\z/)
    return nil if match.nil?

    factor = UNITS[match[2].downcase]
    return nil if factor.nil?

    match[1].to_f * factor
  end
end
