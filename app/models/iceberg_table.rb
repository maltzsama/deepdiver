class IcebergTable < ApplicationRecord
  HEALTH_STATUSES = %w[unknown healthy warning critical].freeze

  belongs_to :catalog
  has_many :maintenance_schedules, dependent: :destroy
  has_many :execution_histories, through: :maintenance_schedules

  enum :health_status, HEALTH_STATUSES.to_h { |s| [ s, s ] }

  validates :namespace, :name, presence: true
  validates :name, uniqueness: { scope: %i[catalog_id namespace] }
  validates :health_score, numericality: { only_integer: true, in: 0..100 }, allow_nil: true

  def fully_qualified_name
    "#{namespace}.#{name}"
  end
end
