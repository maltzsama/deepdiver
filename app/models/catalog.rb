# A data catalog registered in the application and provisioned into Trino.
# Holds the catalog type, endpoint, and connection credential, and derives a
# valid Trino catalog name from the record name.
require "aws-sdk-sts"

class Catalog < ApplicationRecord
  CATALOG_TYPES = %w[polaris nessie].freeze
  S3_AUTH_TYPES = %w[none static sts].freeze
  # How a Nessie catalog is addressed. "rest" uses Nessie's Iceberg REST
  # surface (/iceberg/v1, server-side default warehouse); "native" uses the
  # native /api/v2 API with a client-supplied warehouse and authentication.type
  # — the model Iceberg's own NessieCatalog implements.
  NESSIE_API_MODES = %w[rest native].freeze

  # Mirrors CatalogRow.java v0.2.1 and the trino_catalog_registry CHECK. Any
  # drift here makes the INSERT fail with a constraint violation whose message
  # does not help whoever registered the catalog.
  TRINO_NAME_PATTERN = /\A[a-z][a-z0-9_]{0,62}\z/
  TRINO_RESERVED = %w[system jmx tpch tpcds memory].freeze
  TRINO_NAME_MAX = 63

  has_many :iceberg_tables, dependent: :destroy
  has_one :catalog_credential, dependent: :destroy
  accepts_nested_attributes_for :catalog_credential

  # S3 secret is encrypted at rest, same as CatalogCredential#secret.
  encrypts :s3_secret_key

  validates :name, presence: true, uniqueness: true
  validates :catalog_type, presence: true, inclusion: { in: CATALOG_TYPES }
  validates :endpoint, presence: true, format: { with: /\Ahttps?:\/\/\S+\z/i, message: :must_be_http }
  validates :s3_authentication_type, presence: true, inclusion: { in: S3_AUTH_TYPES }
  validate :nessie_api_mode_is_valid
  validate :trino_catalog_name_is_valid
  validate :endpoint_not_internal
  validate :properties_carry_no_secrets
  validate :nessie_ref_is_valid
  validate :s3_config_valid

  # Which Nessie ref (branch/tag) this catalog reads. Only meaningful for
  # catalog_type "nessie"; when blank the server default branch answers, and a
  # Trino pointed elsewhere diverges silently - names match, numbers don't.
  #
  # Empirical (Nessie 0.108.4): the ref IS the Iceberg REST prefix returned by
  # /v1/config ("prefix-pattern": "{ref}|{warehouse}"); an unknown ref answers
  # HTTP 400 on any /v1/{ref}/... call.
  NESSIE_REF_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._\-]*\z/

  # properties is CONFIGURATION only (warehouse hints and the like). Secrets have
  # exactly one home: CatalogCredential.secret, encrypted. Rejecting them here
  # keeps the plaintext JSON column from ever becoming a side channel.
  PROPERTIES_SECRET_KEYS = %w[bearerToken token client_secret subject_token password].freeze

  # Name of the catalog inside Trino. Derived from the record name, because
  # the application provisions Trino itself. The override exists for
  # when the name is not a valid identifier or collides.
  def trino_catalog_name
    trino_catalog_name_override.presence || derived_trino_catalog_name
  end

  # Derives a valid Trino catalog name from the record name, slugifying it and
  # prefixing names that start with a digit or collide with a reserved word.
  # @return [String] the derived, truncated catalog name
  def derived_trino_catalog_name
    slug = name.to_s.downcase
               .gsub(/[^a-z0-9_]/, "_")
               .gsub(/_+/, "_")
               .gsub(/\A_+|_+\z/, "")

    # Must start with a letter: prefix when it starts with a digit or is empty.
    slug = "cat_#{slug}" unless slug.match?(/\A[a-z]/)

    # Trino reserved: prefix instead of failing, so registration does not get
    # stuck on a name the person chose without knowing the restriction.
    slug = "cat_#{slug}" if TRINO_RESERVED.include?(slug)

    slug.first(TRINO_NAME_MAX)
  end

  # Human-readable representation of the catalog.
  # @return [String] the catalog name
  def to_s
    name
  end

  # Makes a real call and returns what happened, for the "Test" button.
  def verify_connection!
    client = CatalogClientFactory.for(self)
    namespaces = client.namespaces
    # Count the tables too. Namespace discovery succeeding while the table
    # listing is broken reported a verified connection that then imported
    # nothing, and "N namespaces, 0 tables" is what makes that visible at the
    # moment an operator is deciding whether the catalog works.
    table_count = count_tables(client, namespaces)
    catalog_credential&.update!(verified_at: Time.current, verification_error: nil)
    { ok: true, namespace_count: namespaces.size, table_count: table_count }
  rescue StandardError => e
    catalog_credential&.update!(verified_at: Time.current, verification_error: e.message)
    { ok: false, error: e.message }
  end

  # Returns the S3 connector properties for Trino. For "none" returns an empty
  # hash; for "static" the stored access key and secret; for "sts" calls
  # AssumeRole and returns the temporary credentials.
  #
  # @return [Hash{String => String}] properties to merge into Trino connector config
  def resolve_s3_credentials
    case s3_authentication_type
    when "none"
      {}
    when "static"
      {
        "s3.aws-access-key" => s3_access_key,
        "s3.aws-secret-key" => s3_secret_key
      }
    when "sts"
      sts_client = Aws::STS::Client.new(
        access_key_id: s3_access_key,
        secret_access_key: s3_secret_key,
        region: s3_region.presence || "us-east-1",
        endpoint: s3_endpoint.presence
      )
      resp = sts_client.assume_role(
        role_arn: s3_role_arn,
        role_session_name: "deepdiver-#{trino_catalog_name}",
        external_id: s3_external_id.presence
      )
      {
        "s3.aws-access-key" => resp.credentials.access_key_id,
        "s3.aws-secret-key" => resp.credentials.secret_access_key,
        "s3.aws-session-token" => resp.credentials.session_token
      }
    else
      # s3_authentication_type is validated against S3_AUTH_TYPES with a
      # non-null default, so this is unreachable in practice - but callers
      # (TrinoCatalogProjection) do `props.merge!(resolve_s3_credentials)`,
      # and merge!(nil) raises TypeError. An empty hash is the safe no-op.
      {}
    end
  end

  # Namespaces sampled when counting tables for the verification message.
  # Verification is interactive, so the count is a signal that the listing
  # works at all - not an inventory. A catalog with more namespaces than this
  # stops early rather than making the operator wait on a full walk.
  VERIFY_NAMESPACE_SAMPLE = 25

  private

  # Tables found across the sampled namespaces. A namespace whose listing
  # raises contributes nothing rather than failing the whole verification:
  # the connection itself is already proven by the namespace call.
  #
  # @param client [CatalogClient] the catalog client
  # @param namespaces [Array<String>] the discovered namespaces
  # @return [Integer] the number of tables seen
  def count_tables(client, namespaces)
    namespaces.first(VERIFY_NAMESPACE_SAMPLE).sum do |namespace|
      client.tables_in(namespace).size
    rescue StandardError => e
      Rails.logger.warn("verify_connection!: listing #{namespace.inspect} failed: #{e.message}")
      0
    end
  end

  # Validates the EFFECTIVE value - derived or override. Errors surface on the
  # form, not as a CHECK violation at provisioning time.
  def trino_catalog_name_is_valid
    effective = trino_catalog_name

    unless effective.match?(TRINO_NAME_PATTERN)
      errors.add(:trino_catalog_name_override,
                 I18n.t("activerecord.errors.models.catalog.attributes.trino_catalog_name_override.invalid_format",
                        max: TRINO_NAME_MAX, derived: effective))
      return
    end

    return unless TRINO_RESERVED.include?(effective)

    errors.add(:trino_catalog_name_override,
               I18n.t("activerecord.errors.models.catalog.attributes.trino_catalog_name_override.reserved",
                       name: effective, reserved: TRINO_RESERVED.join(", ")))
  end

  BLOCKED_HOSTS = %w[localhost 127.0.0.1 0.0.0.0 169.254.169.254 ::1 metadata.google.internal kubernetes.default.svc].freeze
  BLOCKED_PREFIXES = %w[10. 172.16. 172.17. 172.18. 172.19. 172.20. 172.21. 172.22. 172.23. 172.24. 172.25. 172.26. 172.27. 172.28. 172.29. 172.30. 172.31. 192.168. fd00: fe80:].freeze

  # Guards the config-only properties bag against secret smuggling.
  def properties_carry_no_secrets
    return unless (properties.keys & CatalogCredential::PROPERTIES_SECRET_KEYS).any?

    errors.add(:properties, :must_not_hold_secrets)
  end

  # nessie_ref: optional, Nessie-only, sane ref-shaped string.
  def nessie_ref_is_valid
    return if nessie_ref.blank?

    if catalog_type != "nessie"
      errors.add(:nessie_ref, :only_for_nessie)
    elsif nessie_ref !~ NESSIE_REF_PATTERN
      errors.add(:nessie_ref, :invalid_format)
    end
  end

  # nessie_api_mode / nessie_warehouse: "native" is Nessie-only and requires a
  # warehouse. The "rest" default is valid on any catalog type (it is just the
  # Iceberg REST surface, which Polaris also uses).
  def nessie_api_mode_is_valid
    return unless nessie_api_mode.present?

    if nessie_api_mode == "native" && catalog_type != "nessie"
      errors.add(:nessie_api_mode, :only_for_nessie)
    elsif !NESSIE_API_MODES.include?(nessie_api_mode)
      errors.add(:nessie_api_mode, :invalid_format)
    end

    return unless nessie_api_mode == "native" && nessie_warehouse.blank?

    errors.add(:nessie_warehouse, :required)
  end

  def endpoint_not_internal
    return if endpoint.blank?

    begin
      uri = URI.parse(endpoint)
      host = uri.host.to_s.downcase
    rescue URI::InvalidURIError
      errors.add(:endpoint, :invalid_url)
      return
    end

    return unless BLOCKED_HOSTS.include?(host) || BLOCKED_PREFIXES.any? { |p| host.start_with?(p) }

    errors.add(:endpoint, :blocked_internal)
  end

  def s3_config_valid
    case s3_authentication_type
    when "static"
      errors.add(:s3_access_key, :required) if s3_access_key.blank?
      errors.add(:s3_secret_key, :required) if s3_secret_key.blank?
    when "sts"
      errors.add(:s3_access_key, :required) if s3_access_key.blank?
      errors.add(:s3_secret_key, :required) if s3_secret_key.blank?
      errors.add(:s3_role_arn, :required) if s3_role_arn.blank?
    end
  end
end
