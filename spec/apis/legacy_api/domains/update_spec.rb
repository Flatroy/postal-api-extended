# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ManagementAPI::Domains#update", type: :request do
  let(:admin_user) { create(:user, :admin) }
  let(:management_api_key) { create(:management_api_key, user: admin_user) }
  let(:organization) { create(:organization, owner: admin_user) }
  let(:server) { create(:server, organization: organization) }
  let(:domain) { create(:domain, owner: server, name: "update-domain.example") }
  let(:other_organization) { create(:organization) }
  let(:other_server) { create(:server, organization: other_organization) }
  let(:foreign_domain) { create(:domain, owner: other_server, name: "foreign-domain.example") }

  def json_headers_for(api_key)
    {
      "X-Management-API-Key" => api_key,
      "Content-Type" => "application/json"
    }
  end

  it "updates domain attributes" do
    patch "/api/v1/manage/domains/#{domain.uuid}",
          params: { name: "updated-domain.example", use_for_any: true, outgoing: false }.to_json,
          headers: json_headers_for(management_api_key.key)

    json = JSON.parse(response.body)
    expect(json["status"]).to eq("success")
    expect(json.dig("data", "domain", "name")).to eq("updated-domain.example")
    expect(json.dig("data", "domain", "use_for_any")).to eq(true)
    expect(json.dig("data", "domain", "outgoing")).to eq(false)
  end

  it "updates foreign domains too" do
    patch "/api/v1/manage/domains/#{foreign_domain.uuid}",
          params: { name: "updated-foreign.example" }.to_json,
          headers: json_headers_for(management_api_key.key)

    json = JSON.parse(response.body)
    expect(json["status"]).to eq("success")

    foreign_domain.reload
    expect(foreign_domain.name).to eq("updated-foreign.example")
  end

  def patch_domain(target, params)
    patch "/api/v1/manage/domains/#{target.uuid}",
          params: params.to_json,
          headers: json_headers_for(management_api_key.key)
    JSON.parse(response.body)
  end

  context "when rotating the DKIM key" do
    context "and the current key is not verified in DNS" do
      it "replaces the key immediately and leaves no pending key" do
        previous_key = domain.dkim_private_key

        json = patch_domain(domain, rotate_dkim_key: true)

        expect(json["status"]).to eq("success")
        domain.reload
        expect(domain.dkim_private_key).not_to eq(previous_key)
        expect(domain.pending_dkim_key?).to eq(false)
        expect(json.dig("data", "domain", "dns", "dkim", "pending")).to be_nil
        expect(json.dig("data", "domain", "dns", "dkim", "expected_value")).to eq(domain.dkim_record)
      end
    end

    context "and the current key is verified in DNS" do
      let(:domain) { create(:domain, :dns_all_ok, owner: server, name: "verified-dkim.example") }

      it "keeps signing with the current key and returns the pending record to publish" do
        previous_key = domain.dkim_private_key
        previous_selector = domain.dkim_identifier

        json = patch_domain(domain, rotate_dkim_key: true)

        expect(json["status"]).to eq("success")
        domain.reload
        expect(domain.dkim_private_key).to eq(previous_key)
        expect(domain.dkim_status).to eq("OK")
        expect(domain.pending_dkim_key?).to eq(true)
        expect(domain.pending_dkim_identifier).not_to eq(previous_selector)

        dkim = json.dig("data", "domain", "dns", "dkim")
        expect(dkim["selector"]).to eq(previous_selector)
        expect(dkim["pending"]).to eq(
          "selector" => domain.pending_dkim_identifier,
          "record_name" => "#{domain.pending_dkim_record_name}.verified-dkim.example",
          "record_type" => "TXT",
          "public_key" => domain.pending_dkim_record[/p=([^;]+)/, 1],
          "expected_value" => domain.pending_dkim_record
        )
      end

      it "refuses a second rotation while one is pending" do
        domain.regenerate_dkim_key!
        pending_key = domain.reload.pending_dkim_private_key

        json = patch_domain(domain, rotate_dkim_key: true)

        expect(json["status"]).to eq("error")
        expect(json.dig("data", "code")).to eq("DKIMRotationInProgress")
        expect(domain.reload.pending_dkim_private_key).to eq(pending_key)
      end

      it "cancels a pending rotation and keeps the current key" do
        previous_key = domain.dkim_private_key
        domain.regenerate_dkim_key!

        json = patch_domain(domain, cancel_pending_dkim_key: true)

        expect(json["status"]).to eq("success")
        domain.reload
        expect(domain.pending_dkim_key?).to eq(false)
        expect(domain.dkim_private_key).to eq(previous_key)
        expect(json.dig("data", "domain", "dns", "dkim", "pending")).to be_nil
      end
    end

    it "does not rotate the key when the other attributes are invalid" do
      previous_key = domain.dkim_private_key

      json = patch_domain(domain, rotate_dkim_key: true, verification_method: "Broken")

      expect(json["status"]).to eq("parameter-error")
      expect(domain.reload.dkim_private_key).to eq(previous_key)
    end

    it "returns parameter-error when rotating and cancelling at once" do
      previous_key = domain.dkim_private_key

      json = patch_domain(domain, rotate_dkim_key: true, cancel_pending_dkim_key: true)

      expect(json["status"]).to eq("parameter-error")
      expect(domain.reload.dkim_private_key).to eq(previous_key)
    end

    it "returns parameter-error for an invalid cancel_pending_dkim_key value" do
      json = patch_domain(domain, cancel_pending_dkim_key: "maybe")

      expect(json["status"]).to eq("parameter-error")
    end
  end

  it "accepts numeric boolean values on update" do
    patch "/api/v1/manage/domains/#{domain.uuid}",
          params: { outgoing: 1, incoming: 0, use_for_any: 1 }.to_json,
          headers: json_headers_for(management_api_key.key)

    json = JSON.parse(response.body)
    expect(json["status"]).to eq("success")

    domain.reload
    expect(domain.outgoing).to eq(true)
    expect(domain.incoming).to eq(false)
    expect(domain.use_for_any).to eq(true)
  end

  it "returns parameter-error for invalid verification methods" do
    patch "/api/v1/manage/domains/#{domain.uuid}",
          params: { verification_method: "Broken" }.to_json,
          headers: json_headers_for(management_api_key.key)

    json = JSON.parse(response.body)
    expect(json["status"]).to eq("parameter-error")
  end

  it "returns parameter-error for invalid boolean fields" do
    patch "/api/v1/manage/domains/#{domain.uuid}",
          params: { rotate_dkim_key: "maybe" }.to_json,
          headers: json_headers_for(management_api_key.key)

    json = JSON.parse(response.body)
    expect(json["status"]).to eq("parameter-error")
  end
end
