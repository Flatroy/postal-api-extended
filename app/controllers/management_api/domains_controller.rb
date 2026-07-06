# frozen_string_literal: true

module ManagementAPI
  class DomainsController < BaseController
    STATUS_VALUES = %w[pending pending_dns verified failed].freeze
    DOMAIN_SCOPE_VALUES = %w[server organization].freeze

    def index
      domains = scoped_domains.order(:name)
      domains = apply_scope_filter(domains)
      return if performed?

      domains = apply_status_filter(domains)
      return if performed?

      domains = apply_server_filter(domains)
      return if performed?

      domains = apply_organization_filter(domains)
      return if performed?

      domains = paginate_scope(domains)
      return if performed?

      render_success(
        domains: domains.map { |domain| domain_hash(domain) },
        total: domains.total_count,
        pagination: pagination_data(domains)
      )
    end

    def show
      domain = find_domain
      return unless domain

      render_success(domain: domain_hash(domain, include_details: true))
    end

    def create
      owner = resolve_owner_for_create
      return unless owner

      domain = owner.domains.build(create_attributes)
      ownership_verification_skipped = false

      if current_api_user.admin?
        # Keep parity with UI behavior: admin-created domains skip ownership verification.
        domain.verification_method = "DNS"
        domain.verified_at = Time.now
        ownership_verification_skipped = true
      end

      if domain.save
        render_success(
          domain: domain_hash(domain, include_details: true).merge(
            ownership_verification_skipped: ownership_verification_skipped
          ),
          message: "Domain #{domain.name} created successfully"
        )
      else
        render_parameter_error(domain.errors.full_messages.join(", "))
      end
    end

    def update
      domain = find_domain
      return unless domain

      rotate_dkim_key = normalized_optional_boolean(api_params, "rotate_dkim_key")
      return if rotate_dkim_key == :invalid

      if rotate_dkim_key == true
        domain.generate_dkim_key
      end

      attributes = update_attributes
      return if performed?

      domain.assign_attributes(attributes)

      if domain.save
        render_success(
          domain: domain_hash(domain, include_details: true),
          message: "Domain #{domain.name} updated successfully"
        )
      else
        render_parameter_error(domain.errors.full_messages.join(", "))
      end
    end

    def destroy
      domain = find_domain
      return unless domain

      name = domain.name
      domain.destroy!
      render_success(message: "Domain #{name} has been deleted")
    end

    def verify
      domain = find_domain
      return unless domain

      force = normalized_optional_boolean(api_params, "force")
      return if force == :invalid

      # The management API has no rate limiter yet; force is accepted for compatibility.
      domain.check_dns(:manual)

      render_success(domain: domain_hash(domain, include_details: true))
    rescue StandardError => e
      log_domain_verification_failure(domain, e)
      render_error(
        "DomainVerificationFailed",
        message: "Could not verify DNS records for this domain"
      )
    end

    private

    def find_domain
      domain = scoped_domains.find_by(uuid: params[:uuid])
      return domain if domain

      render_error(
        "DomainNotFound",
        message: "The requested domain could not be found",
        uuid: params[:uuid]
      )
      nil
    end

    def scoped_domains
      server_domains = Domain.where(owner_type: "Server", owner_id: scoped_servers.select(:id))
      organization_domains = Domain.where(owner_type: "Organization", owner_id: scoped_organizations.select(:id))
      server_domains.or(organization_domains).distinct
    end

    def resolve_owner_for_create
      params = api_params
      server_id = params["server_id"]
      organization_id = params["organization_id"]
      requested_scope = params["scope"].to_s.strip

      if server_id.present? && organization_id.present?
        render_parameter_error("server_id and organization_id cannot both be provided")
        return nil
      end

      if requested_scope.present? && !DOMAIN_SCOPE_VALUES.include?(requested_scope)
        render_parameter_error("scope must be one of: #{DOMAIN_SCOPE_VALUES.join(', ')}")
        return nil
      end

      if requested_scope == "server" && organization_id.present?
        render_parameter_error("organization_id cannot be used when scope=server")
        return nil
      end

      if requested_scope == "organization" && server_id.present?
        render_parameter_error("server_id cannot be used when scope=organization")
        return nil
      end

      if server_id.present?
        resolve_server_owner(server_id)
      elsif organization_id.present?
        resolve_organization_owner(organization_id)
      else
        render_parameter_error("server_id or organization_id must be provided")
        nil
      end
    end

    def resolve_server_owner(server_id)
      unless server_id.to_s.match?(/\A\d+\z/)
        render_parameter_error("server_id must be an integer")
        return nil
      end

      server = Server.present.find_by(id: server_id.to_i)
      unless server
        render_error(
          "ServerNotFound",
          message: "The requested server could not be found",
          server_id: server_id.to_i
        )
        return nil
      end

      if scoped_servers.where(id: server.id).exists?
        server
      else
        render_error(
          "AccessDenied",
          message: "server_id is outside your scope",
          server_id: server.id
        )
        nil
      end
    end

    def resolve_organization_owner(organization_id)
      unless organization_id.to_s.match?(/\A\d+\z/)
        render_parameter_error("organization_id must be an integer")
        return nil
      end

      organization = Organization.present.find_by(id: organization_id.to_i)
      unless organization
        render_error(
          "OrganizationNotFound",
          message: "The requested organization could not be found",
          organization_id: organization_id.to_i
        )
        return nil
      end

      if scoped_organizations.where(id: organization.id).exists?
        organization
      else
        render_error(
          "AccessDenied",
          message: "organization_id is outside your scope",
          organization_id: organization.id
        )
        nil
      end
    end

    def apply_scope_filter(domains)
      requested_scope = params[:scope].to_s.strip
      return domains if requested_scope.empty?

      unless DOMAIN_SCOPE_VALUES.include?(requested_scope)
        render_parameter_error("scope must be one of: #{DOMAIN_SCOPE_VALUES.join(', ')}")
        return domains.none
      end

      owner_type = requested_scope == "server" ? "Server" : "Organization"
      domains.where(owner_type: owner_type)
    end

    def apply_status_filter(domains)
      requested_status = params[:status].to_s.strip
      return domains if requested_status.empty?

      unless STATUS_VALUES.include?(requested_status)
        render_parameter_error("status must be one of: #{STATUS_VALUES.join(', ')}")
        return domains.none
      end

      case requested_status
      when "pending"
        domains.where(verified_at: nil)
      when "pending_dns"
        domains.where.not(verified_at: nil).where(spf_status: nil)
      when "verified"
        domains
          .where.not(verified_at: nil)
          .where(spf_status: "OK", dkim_status: "OK")
          .where(mx_status: ["OK", "Missing"], return_path_status: ["OK", "Missing"])
      when "failed"
        domains
          .where.not(verified_at: nil)
          .where.not(spf_status: nil)
          .where.not(spf_status: "OK", dkim_status: "OK", mx_status: ["OK", "Missing"], return_path_status: ["OK", "Missing"])
      else
        domains
      end
    end

    def apply_server_filter(domains)
      server_id = params[:server_id]
      return domains if server_id.blank?

      server = resolve_server_owner(server_id)
      return domains.none if performed?

      domains.where(owner_type: "Server", owner_id: server.id)
    end

    def apply_organization_filter(domains)
      organization_id = params[:organization_id]
      return domains if organization_id.blank?

      organization = resolve_organization_owner(organization_id)
      return domains.none if performed?

      domains.where(owner_type: "Organization", owner_id: organization.id)
    end

    def log_domain_verification_failure(domain, error)
      Rails.logger.error(
        "Management API domain verification failed for domain=#{domain&.uuid || params[:uuid]} " \
        "management_key=#{current_management_api_key&.uuid} user=#{current_api_user&.uuid} " \
        "error_class=#{error.class} error=#{error.message}"
      )
    end

    def create_attributes
      params = api_params
      {
        name: params["name"],
        verification_method: "DNS"
      }
    end

    def update_attributes
      params = api_params
      outgoing = normalized_optional_boolean(params, "outgoing")
      return {} if outgoing == :invalid

      incoming = normalized_optional_boolean(params, "incoming")
      return {} if incoming == :invalid

      use_for_any = normalized_optional_boolean(params, "use_for_any")
      return {} if use_for_any == :invalid

      {
        name: params["name"],
        verification_method: params["verification_method"],
        outgoing: outgoing,
        incoming: incoming,
        use_for_any: use_for_any
      }.reject { |_, value| value == :not_provided }.compact
    end

    def normalized_optional_boolean(params, field_name)
      return :not_provided unless params.key?(field_name)

      normalize_boolean_param(params[field_name], field_name)
    end

    def normalize_boolean_param(raw_value, field_name)
      return true if raw_value == true
      return false if raw_value == false

      if raw_value.is_a?(String)
        normalized = raw_value.strip.downcase
        return true if %w[true 1].include?(normalized)
        return false if %w[false 0].include?(normalized)
      elsif raw_value.is_a?(Numeric)
        return true if raw_value == 1
        return false if raw_value == 0
      end

      render_parameter_error("#{field_name} must be a boolean")
      :invalid
    end

    def domain_scope(domain)
      domain.owner_type == "Server" ? "server" : "organization"
    end

    def domain_status(domain)
      return "pending" unless domain.verified?
      return "pending_dns" unless domain.dns_checked?

      domain.dns_ok? ? "verified" : "failed"
    end

    def domain_status_reason(domain)
      return nil unless domain_status(domain) == "failed"

      return "spf_#{domain.spf_status.to_s.downcase}" unless domain.spf_status == "OK"
      return "dkim_#{domain.dkim_status.to_s.downcase}" unless domain.dkim_status == "OK"
      return "mx_#{domain.mx_status.to_s.downcase}" unless %w[OK Missing].include?(domain.mx_status)
      return "return_path_#{domain.return_path_status.to_s.downcase}" unless %w[OK Missing].include?(domain.return_path_status)

      "dns_invalid"
    end

    def verification_details(domain)
      {
        spf: {
          ok: domain.spf_status == "OK",
          found_value: domain.spf_status == "OK" ? domain.spf_record : nil
        },
        dkim: {
          ok: domain.dkim_status == "OK",
          found_value: domain.dkim_status == "OK" ? domain.dkim_record : nil
        },
        return_path: {
          ok: domain.return_path_status == "OK",
          found_value: domain.return_path_status == "OK" ? Postal::Config.dns.return_path_domain : nil
        },
        dmarc: {
          ok: nil,
          found_value: nil
        }
      }
    end

    def dns_hash(domain)
      dkim_public_key = domain.dkim_record.to_s[/p=([^;]+)/, 1]

      {
        spf: {
          required: true,
          record_name: domain.name,
          record_type: "TXT",
          expected_value: domain.spf_record
        },
        dkim: {
          enabled: true,
          selector: domain.dkim_identifier,
          record_name: [domain.dkim_record_name, domain.name].compact.join("."),
          record_type: "TXT",
          public_key: dkim_public_key,
          expected_value: domain.dkim_record
        },
        return_path: {
          enabled: true,
          host: domain.return_path_domain,
          record_name: domain.return_path_domain,
          record_type: "CNAME",
          expected_value: Postal::Config.dns.return_path_domain
        },
        dmarc: {
          recommended: true,
          record_name: "_dmarc.#{domain.name}",
          record_type: "TXT",
          expected_value: "v=DMARC1; p=none"
        }
      }
    end

    def verification_last_result(domain)
      return "pending" unless domain.dns_checked?

      domain.dns_ok? ? "passed" : "failed"
    end

    def owner_hash_for(domain)
      if domain.owner.is_a?(Server)
        {
          server: {
            id: domain.owner.id,
            uuid: domain.owner.uuid,
            name: domain.owner.name,
            permalink: domain.owner.permalink
          },
          organization: {
            id: domain.owner.organization.id,
            uuid: domain.owner.organization.uuid,
            name: domain.owner.organization.name,
            permalink: domain.owner.organization.permalink
          }
        }
      else
        {
          organization: {
            id: domain.owner.id,
            uuid: domain.owner.uuid,
            name: domain.owner.name,
            permalink: domain.owner.permalink
          }
        }
      end
    end

    def domain_hash(domain, include_details: false)
      hash = {
        id: domain.uuid,
        uuid: domain.uuid,
        internal_id: domain.id,
        name: domain.name,
        scope: domain_scope(domain),
        server_id: domain.owner.is_a?(Server) ? domain.owner_id : nil,
        organization_id: domain.owner.is_a?(Organization) ? domain.owner_id : domain.owner&.organization_id,
        status: domain_status(domain),
        status_reason: domain_status_reason(domain),
        verification_method: domain.verification_method,
        outgoing: domain.outgoing,
        incoming: domain.incoming,
        use_for_any: domain.use_for_any,
        last_verification_at: domain.dns_checked_at&.iso8601,
        created_at: domain.created_at.iso8601,
        updated_at: domain.updated_at.iso8601
      }

      if include_details
        hash[:dns] = dns_hash(domain)
        hash[:verification] = {
          last_result: verification_last_result(domain),
          details: verification_details(domain)
        }
        hash.merge!(owner_hash_for(domain))
      end

      hash
    end
  end
end
