class TeamMembership < ApplicationRecord
  belongs_to :team
  belongs_to :user

  validates :team_id, uniqueness: { scope: :user_id }
end
