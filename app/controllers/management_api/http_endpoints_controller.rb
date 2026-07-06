# frozen_string_literal: true

module ManagementAPI
  class HttpEndpointsController < BaseController
    def index
      endpoints = scoped_http_endpoints
      endpoints = apply_server_filter(endpoints)
      return if performed?

      endpoints = apply_name_filter(endpoints)
      return if performed?

      endpoints = paginate_scope(endpoints)
      return if performed?

      render_success(
        http_endpoints: endpoints.map { |endpoint| endpoint_hash(endpoint) },
        total: endpoints.total_count,
        pagination: pagination_data(endpoints)
      )
    end

    def show
      endpoint = find_http_endpoint
      return unless endpoint

      render_success(http_endpoint: endpoint_hash(endpoint, include_details: true))
    end

    private

    def find_http_endpoint
      endpoint = scoped_http_endpoints.find_by(uuid: params[:uuid])
      return endpoint if endpoint

      render_error(
        "HttpEndpointNotFound",
        message: "The requested HTTP endpoint could not be found",
        uuid: params[:uuid]
      )
      nil
    end

    def scoped_http_endpoints
      HTTPEndpoint.where(server_id: scoped_servers.select(:id))
    end

    def apply_server_filter(endpoints)
      server_id = params[:server_id]
      return endpoints if server_id.blank?

      server = resolve_server(server_id)
      return endpoints.none if performed?

      endpoints.where(server_id: server.id)
    end

    def apply_name_filter(endpoints)
      name = params[:name]
      return endpoints if name.blank?

      endpoints.where(name: name.to_s)
    end

    def resolve_server(server_id)
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

    def endpoint_hash(endpoint, include_details: false)
      hash = {
        id: endpoint.uuid,
        uuid: endpoint.uuid,
        name: endpoint.name,
        server_id: endpoint.server_id,
        url: endpoint.url,
        encoding: endpoint.encoding,
        format: endpoint.format,
        strip_replies: endpoint.strip_replies,
        include_attachments: endpoint.include_attachments,
        timeout: endpoint.timeout,
        last_used_at: endpoint.last_used_at&.iso8601,
        disabled_until: endpoint.disabled_until&.iso8601,
        created_at: endpoint.created_at&.iso8601,
        updated_at: endpoint.updated_at&.iso8601
      }

      if include_details && endpoint.server
        hash[:server] = {
          id: endpoint.server.id,
          uuid: endpoint.server.uuid,
          name: endpoint.server.name,
          permalink: endpoint.server.permalink
        }
      end

      hash
    end
  end
end
