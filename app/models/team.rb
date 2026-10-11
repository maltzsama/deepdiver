# A named group of users.
class Team < ApplicationRecord
  has_many :memberships, class_name: "TeamMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true, uniqueness: true

  # Admin and operator members.
  def responders
    members.where(role: %i[admin operator], status: :active)
  end
end
