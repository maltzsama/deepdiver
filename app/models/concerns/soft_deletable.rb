# Soft-deletes a record by stamping +deleted_at+ instead of removing the row.
#
# The record and everything that points at it (steps, execution history,
# foreign keys) survive, so history and audit trails stay intact. A new record
# can then be created for the same logical slot — callers must scope their
# lookups with +kept+ (there is deliberately no +default_scope+, matching the
# rest of the codebase) and the owning table needs a *partial* unique index
# (+where: "deleted_at IS NULL"+) so a discarded row does not block a fresh one.
#
# Include it on a model that has a +deleted_at+ datetime column:
#
#   class MaintenancePlan < ApplicationRecord
#     include SoftDeletable
#   end
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :kept, -> { where(deleted_at: nil) }
    scope :discarded, -> { where.not(deleted_at: nil) }

    # +destroy+ is soft: it stamps +deleted_at+ and leaves the row in place.
    # +update_column+ is deliberate — it bypasses validations (a plan whose
    # table is currently unaddressable in Trino must still be deletable) and
    # callbacks, so +dependent:+ never runs and steps / execution history stay
    # attached to the discarded record.
    def destroy
      return false if destroyed? || discarded? || new_record?
      update_column(:deleted_at, Time.current)
    end

    def destroy!
      destroy || raise(ActiveRecord::RecordNotDestroyed.new(self))
    end

    # Clears the stamp, restoring the record to the kept scopes. Also bypasses
    # validations, matching +destroy+.
    def undiscard
      return false unless discarded?
      update_column(:deleted_at, nil)
    end
    alias restore undiscard

    def discarded?
      deleted_at.present?
    end
    alias deleted? discarded?

    def kept?
      deleted_at.nil?
    end
  end
end
