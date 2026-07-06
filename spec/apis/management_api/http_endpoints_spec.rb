# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Management API http endpoints", type: :request do
  let(:admin_user) { create(:user, :admin) }
  let(:management_api_key) { create(:management_api_key, user: admin_user) }
  let(:raw_key) { management_api_key.key }

  let!(:organization) { create(:organization, owner: admin_user) }
  let!(:server) { create(:server, organization: organization) }
  let!(:http_endpoint) { create(:http_endpoint, server: server, name: "postal - web") }

  def api_headers
    { "X-Management-API-Key" => raw_key }
  end

  def parsed_data
    JSON.parse(response.body).fetch("data")
  end

  describe "authentication" do
    it "rejects requests without a management API key" do
      get "/api/v1/manage/http_endpoints"
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("AccessDenied")
    end

    it "rejects requests with an invalid management API key" do
      get "/api/v1/manage/http_endpoints", headers: { "X-Management-API-Key" => "nope" }
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("InvalidManagementAPIKey")
    end
  end

  describe "GET /api/v1/manage/http_endpoints" do
    it "lists http endpoints within scope" do
      get "/api/v1/manage/http_endpoints", headers: api_headers
      expect(response).to have_http_status(:ok)
      data = parsed_data
      uuids = data["http_endpoints"].map { |e| e["uuid"] }
      expect(uuids).to include(http_endpoint.uuid)
      expect(data["pagination"]).to include("page", "per_page", "total", "total_pages")
    end

    it "filters by server_id" do
      other_server = create(:server, organization: organization)
      create(:http_endpoint, server: other_server, name: "other")

      get "/api/v1/manage/http_endpoints?server_id=#{server.id}", headers: api_headers
      server_ids = parsed_data["http_endpoints"].map { |e| e["server_id"] }
      expect(server_ids).to all(eq(server.id))
    end

    it "filters by name" do
      get "/api/v1/manage/http_endpoints?name=postal%20-%20web", headers: api_headers
      names = parsed_data["http_endpoints"].map { |e| e["name"] }
      expect(names).to all(eq("postal - web"))
    end

    it "rejects a non-integer server_id" do
      get "/api/v1/manage/http_endpoints?server_id=abc", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("parameter-error")
    end
  end

  describe "GET /api/v1/manage/http_endpoints/:uuid" do
    it "returns the endpoint with server details" do
      get "/api/v1/manage/http_endpoints/#{http_endpoint.uuid}", headers: api_headers
      expect(response).to have_http_status(:ok)
      endpoint = parsed_data["http_endpoint"]
      expect(endpoint["uuid"]).to eq(http_endpoint.uuid)
      expect(endpoint["url"]).to eq(http_endpoint.url)
      expect(endpoint["server"]["uuid"]).to eq(server.uuid)
    end

    it "returns HttpEndpointNotFound for an unknown uuid" do
      get "/api/v1/manage/http_endpoints/does-not-exist", headers: api_headers
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json.dig("data", "code")).to eq("HttpEndpointNotFound")
    end
  end
end
