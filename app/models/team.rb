# A named group of users that error events can be assigned to. Assigning to a
# team notifies every admin/operator member; the first member to acknowledge
# takes ownership of the event.
class Team < ApplicationRecord
  has_many :memberships, class_name: "TeamMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true, uniqueness: true

  # Admin and operator members are actionable assignees for error events.
  def responders
    members.where(role: %i[admin operator], status: :active)
  end
end
