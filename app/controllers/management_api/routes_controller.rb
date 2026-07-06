# frozen_string_literal: true

module ManagementAPI
  class RoutesController < BaseController
    ENDPOINT_TYPES = %w[SMTPEndpoint HTTPEndpoint AddressEndpoint].freeze
    SPAM_MODE_VALUES = Route::SPAM_MODES
    MODE_VALUES = Route::MODES

    def index
      routes = scoped_routes
      routes = apply_server_filter(routes)
      return if performed?

      routes = apply_domain_filter(routes)
      return if performed?

      routes = apply_name_filter(routes)
      return if performed?

      routes = paginate_scope(routes)
      return if performed?

      render_success(
        routes: routes.map { |route| route_hash(route) },
        total: routes.total_count,
        pagination: pagination_data(routes)
      )
    end

    def show
      route = find_route
      return unless route

      render_success(route: route_hash(route, include_details: true))
    end

    def create
      server = resolve_server
      return unless server

      domain = resolve_domain_for_create(server)
      return if performed?

      endpoint = resolve_endpoint_for_create(server)
      return if performed?

      spam_mode = create_spam_mode
      return if performed?

      mode = endpoint ? "Endpoint" : create_mode
      return if performed?

      route = server.routes.build(
        name: create_name,
        domain: domain,
        spam_mode: spam_mode,
        mode: mode
      )
      route.endpoint = endpoint if endpoint

      if route.save
        render_success(
          route: route_hash(route, include_details: true),
          message: "Route #{route.description} created successfully"
        )
      else
        render_parameter_error(route.errors.full_messages.join(", "))
      end
    end

    def update
      route = find_route
      return unless route

      attributes = update_attributes(route)
      return if performed?

      route.assign_attributes(attributes)

      if route.save
        render_success(
          route: route_hash(route, include_details: true),
          message: "Route #{route.description} updated successfully"
        )
      else
        render_parameter_error(route.errors.full_messages.join(", "))
      end
    end

    def destroy
      route = find_route
      return unless route

      description = route.description
      route.destroy!
      render_success(message: "Route #{description} has been deleted")
    end

    private

    def find_route
      route = scoped_routes.find_by(uuid: params[:uuid])
      return route if route

      render_error(
        "RouteNotFound",
        message: "The requested route could not be found",
        uuid: params[:uuid]
      )
      nil
    end

    def scoped_routes
      Route.where(server_id: scoped_servers.select(:id))
    end

    def resolve_server(server_id = nil)
      server_id ||= api_params["server_id"]
      if server_id.blank?
        render_parameter_error("server_id must be provided")
        return nil
      end

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

    def resolve_domain_for_create(server)
      domain_id = api_params["domain_id"]
      return nil if domain_id.blank?

      unless domain_id.to_s.match?(/\A\d+\z/)
        render_parameter_error("domain_id must be an integer")
        return nil
      end

      domain = Domain.find_by(id: domain_id.to_i)
      unless domain
        render_error(
          "DomainNotFound",
          message: "The requested domain could not be found",
          domain_id: domain_id.to_i
        )
        return nil
      end

      unless [server, server.organization].include?(domain.owner)
        render_parameter_error("domain_id does not belong to the chosen server or its organization")
        return nil
      end

      domain
    end

    def resolve_endpoint_for_create(server)
      endpoint_type = api_params["endpoint_type"]
      endpoint_uuid = api_params["endpoint_uuid"]

      if endpoint_type.blank? && endpoint_uuid.blank?
        return nil
      end

      if endpoint_type.blank? || endpoint_uuid.blank?
        render_parameter_error("endpoint_type and endpoint_uuid must both be provided")
        return nil
      end

      unless ENDPOINT_TYPES.include?(endpoint_type.to_s)
        render_parameter_error("endpoint_type must be one of: #{ENDPOINT_TYPES.join(', ')}")
        return nil
      end

      endpoint = endpoint_type.to_s.constantize.find_by_uuid(endpoint_uuid.to_s)
      unless endpoint
        render_error(
          "EndpointNotFound",
          message: "The requested endpoint could not be found",
          endpoint_type: endpoint_type.to_s,
          endpoint_uuid: endpoint_uuid.to_s
        )
        return nil
      end

      unless endpoint.server == server
        render_parameter_error("endpoint does not belong to the chosen server")
        return nil
      end

      endpoint
    end

    def create_name
      name = api_params["name"]
      return "*" if name.blank?

      name.to_s
    end

    def create_spam_mode
      spam_mode = api_params["spam_mode"]
      return Route::SPAM_MODES.first if spam_mode.blank?

      unless SPAM_MODE_VALUES.include?(spam_mode.to_s)
        render_parameter_error("spam_mode must be one of: #{SPAM_MODE_VALUES.join(', ')}")
        return nil
      end

      spam_mode.to_s
    end

    def create_mode
      mode = api_params["mode"]
      return nil if mode.blank?

      unless MODE_VALUES.include?(mode.to_s)
        render_parameter_error("mode must be one of: #{MODE_VALUES.join(', ')}")
        return nil
      end

      mode.to_s
    end

    def update_attributes(route)
      params = api_params
      attributes = {}

      if params.key?("name")
        name = params["name"].to_s
        attributes[:name] = name
      end

      if params.key?("spam_mode")
        spam_mode = params["spam_mode"].to_s
        unless SPAM_MODE_VALUES.include?(spam_mode)
          render_parameter_error("spam_mode must be one of: #{SPAM_MODE_VALUES.join(', ')}")
          return nil
        end
        attributes[:spam_mode] = spam_mode
      end

      if params.key?("domain_id")
        domain_id = params["domain_id"]
        if domain_id.blank?
          attributes[:domain_id] = nil
        else
          domain = resolve_domain_for_update(route.server, domain_id)
          return nil if performed?
          attributes[:domain_id] = domain&.id
        end
      end

      if params.key?("endpoint_type") || params.key?("endpoint_uuid")
        endpoint = resolve_endpoint_for_update(route.server, params)
        return nil if performed?
        if endpoint
          attributes[:endpoint] = endpoint
          attributes[:mode] = "Endpoint"
        elsif params["endpoint_uuid"].blank? && params["endpoint_type"].blank?
          attributes[:endpoint] = nil
          mode = params["mode"]
          if mode.present?
            unless MODE_VALUES.include?(mode.to_s)
              render_parameter_error("mode must be one of: #{MODE_VALUES.join(', ')}")
              return nil
            end
            attributes[:mode] = mode.to_s
          end
        end
      elsif params.key?("mode")
        mode = params["mode"].to_s
        unless MODE_VALUES.include?(mode)
          render_parameter_error("mode must be one of: #{MODE_VALUES.join(', ')}")
          return nil
        end
        if mode == "Endpoint"
          attributes[:endpoint] = route.endpoint
        else
          attributes[:endpoint] = nil
          attributes[:mode] = mode
        end
      end

      attributes
    end

    def resolve_domain_for_update(server, domain_id)
      unless domain_id.to_s.match?(/\A\d+\z/)
        render_parameter_error("domain_id must be an integer")
        return nil
      end

      domain = Domain.find_by(id: domain_id.to_i)
      unless domain
        render_error(
          "DomainNotFound",
          message: "The requested domain could not be found",
          domain_id: domain_id.to_i
        )
        return nil
      end

      unless [server, server.organization].include?(domain.owner)
        render_parameter_error("domain_id does not belong to the chosen server or its organization")
        return nil
      end

      domain
    end

    def resolve_endpoint_for_update(server, params)
      endpoint_type = params["endpoint_type"]
      endpoint_uuid = params["endpoint_uuid"]
      return nil if endpoint_type.blank? && endpoint_uuid.blank?

      if endpoint_type.blank? || endpoint_uuid.blank?
        render_parameter_error("endpoint_type and endpoint_uuid must both be provided")
        return nil
      end

      unless ENDPOINT_TYPES.include?(endpoint_type.to_s)
        render_parameter_error("endpoint_type must be one of: #{ENDPOINT_TYPES.join(', ')}")
        return nil
      end

      endpoint = endpoint_type.to_s.constantize.find_by_uuid(endpoint_uuid.to_s)
      unless endpoint
        render_error(
          "EndpointNotFound",
          message: "The requested endpoint could not be found",
          endpoint_type: endpoint_type.to_s,
          endpoint_uuid: endpoint_uuid.to_s
        )
        return nil
      end

      unless endpoint.server == server
        render_parameter_error("endpoint does not belong to the chosen server")
        return nil
      end

      endpoint
    end

    def apply_server_filter(routes)
      server_id = params[:server_id]
      return routes if server_id.blank?

      server = resolve_server(server_id)
      return routes.none if performed?

      routes.where(server_id: server.id)
    end

    def apply_domain_filter(routes)
      domain_id = params[:domain_id]
      return routes if domain_id.blank?

      unless domain_id.to_s.match?(/\A\d+\z/)
        render_parameter_error("domain_id must be an integer")
        return routes.none
      end

      routes.where(domain_id: domain_id.to_i)
    end

    def apply_name_filter(routes)
      name = params[:name]
      return routes if name.blank?

      routes.where(name: name.to_s)
    end

    def endpoint_hash(route)
      return nil unless route.endpoint

      {
        type: route.endpoint_type,
        uuid: route.endpoint&.uuid,
        name: route.endpoint&.name
      }
    end

    def route_hash(route, include_details: false)
      hash = {
        id: route.uuid,
        uuid: route.uuid,
        name: route.name,
        server_id: route.server_id,
        domain_id: route.domain_id,
        mode: route.mode,
        spam_mode: route.spam_mode,
        token: route.token,
        description: route.description,
        wildcard: route.wildcard?,
        endpoint: endpoint_hash(route),
        created_at: route.created_at&.iso8601,
        updated_at: route.updated_at&.iso8601
      }

      if include_details && route.domain
        hash[:domain] = {
          id: route.domain.uuid,
          uuid: route.domain.uuid,
          name: route.domain.name
        }
      end

      hash
    end
  end
end
