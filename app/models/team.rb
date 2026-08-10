class Team < ApplicationRecord
  has_many :memberships, class_name: "TeamMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user
  has_many :users, through: :memberships
  has_many :catalog_scopes, class_name: "TeamCatalogScope", dependent: :destroy
  has_many :catalogs, through: :catalog_scopes

  validates :name, presence: true, uniqueness: true

  # An empty catalog scope means the team may act on every catalog.
  def scoped_to_all_catalogs?
    catalog_ids.empty?
  end

  def manages?(catalog)
    scoped_to_all_catalogs? || catalog_ids.include?(catalog.id)
  end
end
