# Enforces the singleton-row contract of a model backed by a table with a
# unique singleton_key index. instance returns (or creates) the single row;
# on a bootstrap race the loser rescues RecordNotUnique and re-reads the
# winner's row instead of raising.
module SingletonModel
  extend ActiveSupport::Concern

  class_methods do
    # The single row, creating it with the given defaults on first access.
    #
    # @param defaults [Hash] attributes for the initial row
    # @return [ApplicationRecord] the singleton row
    def instance(defaults = {})
      first_or_create!(defaults)
    rescue ActiveRecord::RecordNotUnique
      # Two processes raced the empty-table insert; the other one won.
      # first!
      first!
    end
  end
end
