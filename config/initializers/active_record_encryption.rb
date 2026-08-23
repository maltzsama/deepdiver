# Active Record Encryption keys.
#
# Production injects the real values via env vars from the Kubernetes Secret
# (ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY /
# _KEY_DERIVATION_SALT). Development and test fall back to throwaway keys so
# catalog credentials can be encrypted locally. The values are read eagerly
# here because the railtie merges config.active_record.encryption into the
# encryption configuration.
if Rails.env.development? || Rails.env.test?
  ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||= "7L2VKrXkkqfYAAoEKHNQp9QUYZqg1E4o"
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||= "tppqJTZfiAmQQrG0xNllU4HDn8s8XEkt"
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||= "BhVzKPgZ2aVDYuzgyFZMIHtcg4BOXT7D"
end

Rails.application.config.active_record.encryption.primary_key =
  ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
Rails.application.config.active_record.encryption.deterministic_key =
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
