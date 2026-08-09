class IcebergTable < ApplicationRecord
  HEALTH_STATUSES = %w[unknown healthy warning critical].freeze

  belongs_to :catalog
  has_many :maintenance_schedules, dependent: :destroy
  has_one :maintenance_plan, dependent: :destroy
  has_many :execution_histories, dependent: :destroy

  enum :health_status, HEALTH_STATUSES.to_h { |s| [ s, s ] }

  validates :namespace, :name, presence: true
  validates :name, uniqueness: { scope: %i[catalog_id namespace] }
  validates :health_score, numericality: { only_integer: true, in: 0..100 }, allow_nil: true

  def fully_qualified_name
    "#{namespace}.#{name}"
  end

  # Trino SQL identifier, always exactly three parts: catalog.schema.table.
  # The whole namespace stays inside a single quoted part; the Iceberg
  # connector rebuilds the nested Namespace from its separator. Never split
  # a dotted namespace into multiple identifier parts.
  #   "catalog"."ns1.ns2.ns3"."table"
  def trino_identifier
    [ catalog.trino_catalog_name, namespace, name ].map { |part| quote_identifier(part) }.join(".")
  end

  private

  def quote_identifier(part)
    %("#{part.to_s.gsub('"', '""')}")
  end
end
