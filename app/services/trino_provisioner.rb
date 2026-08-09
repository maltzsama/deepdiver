# Provisioning is behind an adapter, in the same pattern TrinoRuntime already
# uses with fake/real. If the Baleia catalog-store plugin does not load, switch
# TRINO_PROVISIONER=chart and nothing else changes.
class TrinoProvisioner
  class Error < StandardError; end

  class << self
    delegate :exists?, :healthy?, :rollout_complete?, :idle?,
             :create!, :destroy!, :wait_gone!, to: :adapter

    def adapter
      @adapter ||= case ENV.fetch("TRINO_PROVISIONER", "chart")
      when "baleia" then BaleiaTrinoProvisioner.new
      when "fake"   then FakeTrinoProvisioner.new
      else               ChartTrinoProvisioner.new
      end
    end

    attr_writer :adapter

    def reset_adapter! = @adapter = nil
  end
end
