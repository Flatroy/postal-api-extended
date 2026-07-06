# frozen_string_literal: true

module ManagementAPI
  class BaseController < ActionController::Base
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 100

    skip_before_action :set_browser_id
    skip_before_action :verify_authenticity_token

    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_json_parse_error

    before_action :start_timer
    before_action :authenticate_with_management_api_key

    private

    def api_params
      if request.headers["content-type"] =~ /\Aapplication\/json/
        return params.to_unsafe_hash
      end

      if params["params"].present?
        return JSON.parse(params["params"])
      end

      {}
    end

    def start_timer
      @start_time = Time.now.to_f
    end

    def authenticate_with_management_api_key
      key = request.headers["X-Management-API-Key"]
      if key.blank?
        render_error "AccessDenied",
                     message: "Must be authenticated for management API access."
        return
      end

      management_api_key = ManagementAPIKey.authenticate(key)
      if management_api_key.nil?
        render_error "InvalidManagementAPIKey",
                     message: "The API token provided in X-Management-API-Key was not valid."
        return
      end

      if management_api_key.revoked?
        render_error "ManagementAPIKeyRevoked",
                     message: "The management API key has been revoked."
        return
      end

      if management_api_key.user.nil? || !management_api_key.user.admin?
        render_error "AccessDenied",
                     message: "Management API keys require an active admin user."
        return
      end

      management_api_key.use
      @current_management_api_key = management_api_key
      @current_api_user = management_api_key.user
    end

    def render_success(data)
      render json: { status: "success",
                     time: (Time.now.to_f - @start_time).round(3),
                     flags: {},
                     data: data }
    end

    def render_error(code, data = {})
      render json: { status: "error",
                     time: (Time.now.to_f - @start_time).round(3),
                     flags: {},
                     data: data.merge(code: code) }
    end

    def render_parameter_error(message)
      render json: { status: "parameter-error",
                     time: (Time.now.to_f - @start_time).round(3),
                     flags: {},
                     data: { message: message } }
    end

    def handle_json_parse_error
      render_parameter_error "Request body must contain valid JSON."
    end

    def current_management_api_key
      @current_management_api_key
    end

    def current_api_user
      @current_api_user
    end

    def paginate_scope(scope)
      options = pagination_options
      return if performed?

      scope.page(options[:page]).per(options[:per_page])
    end

    def pagination_data(scope)
      {
        page: scope.current_page,
        per_page: scope.limit_value,
        total: scope.total_count,
        total_pages: scope.total_pages
      }
    end

    def scoped_organizations_for_current_api_user
      return Organization.present.none unless current_api_user
      return Organization.present if current_api_user.admin?

      Organization
        .present
        .left_outer_joins(:organization_users)
        .where(
          "organizations.owner_id = :user_id OR (organization_users.user_type = 'User' AND organization_users.user_id = :user_id)",
          user_id: current_api_user.id
        )
        .distinct
    end

    def scoped_organizations
      scoped_organizations_for_current_api_user
    end

    def scoped_servers
      Server.present.where(organization_id: scoped_organizations.select(:id))
    end

    def pagination_options
      page = parse_positive_integer_param(params[:page], "page", default: DEFAULT_PAGE)
      return if performed?

      per_page = parse_positive_integer_param(params[:per_page], "per_page", default: DEFAULT_PER_PAGE)
      return if performed?

      if per_page > MAX_PER_PAGE
        render_parameter_error("per_page must be less than or equal to #{MAX_PER_PAGE}")
        return
      end

      { page: page, per_page: per_page }
    end

    def parse_positive_integer_param(value, field_name, default:)
      return default if value.blank?

      integer = Integer(value, 10)
      if integer < 1
        render_parameter_error("#{field_name} must be greater than or equal to 1")
        return
      end

      integer
    rescue ArgumentError, TypeError
      render_parameter_error("#{field_name} must be an integer")
      nil
    end
  end
end
