class Catalog < ApplicationRecord
  CATALOG_TYPES = %w[polaris nessie].freeze

  has_many :iceberg_tables, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :catalog_type, presence: true, inclusion: { in: CATALOG_TYPES }
  validates :endpoint, presence: true

  def to_s
    name
  end
end
