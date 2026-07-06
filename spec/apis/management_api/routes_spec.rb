# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Management API routes", type: :request do
  let(:admin_user) { create(:user, :admin) }
  let(:management_api_key) { create(:management_api_key, user: admin_user) }
  let(:raw_key) { management_api_key.key }

  let!(:organization) { create(:organization, owner: admin_user) }
  let!(:server) { create(:server, organization: organization) }
  let!(:domain) { create(:domain, owner: server, name: "routes.example") }
  let!(:http_endpoint) { create(:http_endpoint, server: server, name: "postal - web") }
  let!(:route) do
    create(:route, server: server, domain: domain, name: "*",
                   endpoint: http_endpoint, mode: "Endpoint", spam_mode: "Mark")
  end

  def api_headers
    { "X-Management-API-Key" => raw_key }
  end

  def api_json_headers
    api_headers.merge("Content-Type" => "application/json")
  end

  def parsed_data
    JSON.parse(response.body).fetch("data")
  end

  describe "authentication" do
    it "rejects requests without a management API key" do
      get "/api/v1/manage/routes"
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("AccessDenied")
    end

    it "rejects requests with an invalid management API key" do
      get "/api/v1/manage/routes", headers: { "X-Management-API-Key" => "does-not-exist" }
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("InvalidManagementAPIKey")
    end

    it "rejects revoked keys" do
      management_api_key.update!(revoked_at: Time.current)
      get "/api/v1/manage/routes", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("ManagementAPIKeyRevoked")
    end

    it "rejects non-admin key owners" do
      admin_user.update!(admin: false)
      get "/api/v1/manage/routes", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("ManagementAPIKeyRevoked")
    end
  end

  describe "GET /api/v1/manage/routes" do
    it "lists routes within scope" do
      get "/api/v1/manage/routes", headers: api_headers
      expect(response).to have_http_status(:ok)
      data = parsed_data
      names = data["routes"].map { |r| r["name"] }
      expect(names).to include(route.name)
      expect(data["total"]).to be >= 1
      expect(data["pagination"]).to include("page", "per_page", "total", "total_pages")
    end

    it "filters by server_id" do
      other_server = create(:server, organization: organization)
      create(:route, server: other_server, domain: create(:domain, owner: other_server))

      get "/api/v1/manage/routes?server_id=#{server.id}", headers: api_headers
      server_ids = parsed_data["routes"].map { |r| r["server_id"] }
      expect(server_ids).to all(eq(server.id))
    end

    it "filters by domain_id" do
      get "/api/v1/manage/routes?domain_id=#{domain.id}", headers: api_headers
      domain_ids = parsed_data["routes"].map { |r| r["domain_id"] }
      expect(domain_ids).to all(eq(domain.id))
    end

    it "filters by name" do
      get "/api/v1/manage/routes?name=*", headers: api_headers
      names = parsed_data["routes"].map { |r| r["name"] }
      expect(names).to all(eq("*"))
    end

    it "rejects a non-integer server_id" do
      get "/api/v1/manage/routes?server_id=abc", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end
  end

  describe "GET /api/v1/manage/routes/:uuid" do
    it "returns the route with details" do
      get "/api/v1/manage/routes/#{route.uuid}", headers: api_headers
      expect(response).to have_http_status(:ok)
      expect(parsed_data["route"]["uuid"]).to eq(route.uuid)
      expect(parsed_data["route"]["domain"]["name"]).to eq(domain.name)
      expect(parsed_data["route"]["endpoint"]["type"]).to eq("HTTPEndpoint")
    end

    it "returns RouteNotFound for an unknown uuid" do
      get "/api/v1/manage/routes/does-not-exist", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("RouteNotFound")
    end
  end

  describe "POST /api/v1/manage/routes" do
    it "creates a catch-all route pointing at an HTTP endpoint" do
      expect do
        post "/api/v1/manage/routes",
             params: {
               server_id: server.id,
               domain_id: domain.id,
               name: "*",
               endpoint_type: "HTTPEndpoint",
               endpoint_uuid: http_endpoint.uuid,
               spam_mode: "Mark"
             }.to_json,
             headers: api_json_headers
      end.to change(Route, :count).by(1)

      expect(response).to have_http_status(:ok)
      created = parsed_data["route"]
      expect(created["name"]).to eq("*")
      expect(created["mode"]).to eq("Endpoint")
      expect(created["endpoint"]["uuid"]).to eq(http_endpoint.uuid)
      expect(created["domain"]["name"]).to eq(domain.name)
    end

    it "defaults the name to a catch-all wildcard when omitted" do
      post "/api/v1/manage/routes",
           params: {
             server_id: server.id,
             domain_id: domain.id,
             endpoint_type: "HTTPEndpoint",
             endpoint_uuid: http_endpoint.uuid
           }.to_json,
           headers: api_json_headers
      expect(response).to have_http_status(:ok)
      expect(parsed_data["route"]["name"]).to eq("*")
    end

    it "requires a server_id" do
      post "/api/v1/manage/routes",
           params: { domain_id: domain.id, name: "*" }.to_json,
           headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end

    it "rejects an unknown server_id" do
      post "/api/v1/manage/routes",
           params: { server_id: 999_999, domain_id: domain.id, name: "*" }.to_json,
           headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("ServerNotFound")
    end

    it "rejects a domain that does not belong to the server" do
      other_server = create(:server, organization: organization)
      other_domain = create(:domain, owner: other_server, name: "other.example")

      post "/api/v1/manage/routes",
           params: {
             server_id: server.id,
             domain_id: other_domain.id,
             name: "*",
             endpoint_type: "HTTPEndpoint",
             endpoint_uuid: http_endpoint.uuid
           }.to_json,
           headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end

    it "rejects an endpoint that does not belong to the server" do
      other_server = create(:server, organization: organization)
      other_endpoint = create(:http_endpoint, server: other_server)

      post "/api/v1/manage/routes",
           params: {
             server_id: server.id,
             domain_id: domain.id,
             name: "*",
             endpoint_type: "HTTPEndpoint",
             endpoint_uuid: other_endpoint.uuid
           }.to_json,
           headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end

    it "rejects an invalid endpoint_type" do
      post "/api/v1/manage/routes",
           params: {
             server_id: server.id,
             domain_id: domain.id,
             name: "*",
             endpoint_type: "NopeEndpoint",
             endpoint_uuid: http_endpoint.uuid
           }.to_json,
           headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end

    it "rejects an invalid spam_mode" do
      post "/api/v1/manage/routes",
           params: {
             server_id: server.id,
             domain_id: domain.id,
             name: "*",
             endpoint_type: "HTTPEndpoint",
             endpoint_uuid: http_endpoint.uuid,
             spam_mode: "Delete"
           }.to_json,
           headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end
  end

  describe "PATCH /api/v1/manage/routes/:uuid" do
    it "updates the spam_mode" do
      patch "/api/v1/manage/routes/#{route.uuid}",
            params: { spam_mode: "Quarantine" }.to_json,
            headers: api_json_headers
      expect(response).to have_http_status(:ok)
      expect(route.reload.spam_mode).to eq("Quarantine")
    end

    it "updates the name" do
      patch "/api/v1/manage/routes/#{route.uuid}",
            params: { name: "info" }.to_json,
            headers: api_json_headers
      expect(response).to have_http_status(:ok)
      expect(route.reload.name).to eq("info")
    end

    it "rejects an invalid spam_mode" do
      patch "/api/v1/manage/routes/#{route.uuid}",
            params: { spam_mode: "Delete" }.to_json,
            headers: api_json_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end
  end

  describe "DELETE /api/v1/manage/routes/:uuid" do
    it "deletes the route" do
      expect do
        delete "/api/v1/manage/routes/#{route.uuid}", headers: api_headers
      end.to change(Route, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(parsed_data["message"]).to include("deleted")
    end

    it "returns RouteNotFound for an unknown uuid" do
      delete "/api/v1/manage/routes/does-not-exist", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("RouteNotFound")
    end
  end
end
