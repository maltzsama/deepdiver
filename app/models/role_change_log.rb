# Audit trail entry recording a change to a user's role: who was changed, who
# changed it, and between which roles.
class RoleChangeLog < ApplicationRecord
  belongs_to :user
  belongs_to :changed_by, class_name: "User"

  validates :from_role, :to_role, presence: true

  delegate :email, to: :user, prefix: true
end
