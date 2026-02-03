# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcMap::MapController do
  fab!(:member_group) { Fabricate(:group, name: "vereinsmitglieder") }
  fab!(:member_user) { Fabricate(:user) }
  fab!(:non_member_user) { Fabricate(:user) }

  before do
    SiteSetting.vzekc_map_enabled = true
    SiteSetting.vzekc_map_members_group_name = "vereinsmitglieder"
    member_group.add(member_user)
  end

  describe "GET /vzekc-map/locations.json" do
    context "when not logged in" do
      it "returns 403 forbidden" do
        get "/vzekc-map/locations.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as non-member" do
      before { sign_in(non_member_user) }

      it "returns 403 forbidden" do
        get "/vzekc-map/locations.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as member" do
      before { sign_in(member_user) }

      it "returns 200 with empty locations when no users have geoinformation" do
        get "/vzekc-map/locations.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json).to have_key("locations")
        expect(json["locations"]).to eq([])
      end

      context "with users having geoinformation" do
        fab!(:user_with_geo) { Fabricate(:user) }

        before do
          UserCustomField.create!(
            user: user_with_geo,
            name: "Geoinformation",
            value: "geo:52.520,13.405?z=15"
          )
        end

        it "returns locations with user info and coordinates" do
          get "/vzekc-map/locations.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["locations"].length).to eq(1)

          location = json["locations"].first
          expect(location["user"]["id"]).to eq(user_with_geo.id)
          expect(location["user"]["username"]).to eq(user_with_geo.username)
          expect(location["user"]).to have_key("avatar_template")

          expect(location["coordinates"].length).to eq(1)
          expect(location["coordinates"].first["lat"]).to eq(52.520)
          expect(location["coordinates"].first["lng"]).to eq(13.405)
          expect(location["coordinates"].first["zoom"]).to eq(15)
        end

        it "parses multiple coordinate formats" do
          UserCustomField.create!(
            user: member_user,
            name: "Geoinformation",
            value: "50.554224,9.676251"
          )

          get "/vzekc-map/locations.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["locations"].length).to eq(2)
        end

        it "parses OpenStreetMap URLs" do
          user_with_geo.custom_fields["Geoinformation"] =
            "https://www.openstreetmap.org/?#map=19/52.129158/11.604304"
          user_with_geo.save_custom_fields

          get "/vzekc-map/locations.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          location = json["locations"].first
          expect(location["coordinates"].first["lat"]).to be_within(0.0001).of(52.129158)
          expect(location["coordinates"].first["lng"]).to be_within(0.0001).of(11.604304)
          expect(location["coordinates"].first["zoom"]).to eq(19)
        end

        it "handles users with multiple locations" do
          user_with_geo.custom_fields["Geoinformation"] = "geo:52.520,13.405 geo:48.856,2.352"
          user_with_geo.save_custom_fields

          get "/vzekc-map/locations.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          location = json["locations"].first
          expect(location["coordinates"].length).to eq(2)
        end

        it "skips users with invalid geoinformation" do
          UserCustomField.create!(
            user: non_member_user,
            name: "Geoinformation",
            value: "invalid data"
          )

          get "/vzekc-map/locations.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          # Only user_with_geo should be returned, not non_member_user with invalid data
          expect(json["locations"].length).to eq(1)
          expect(json["locations"].first["user"]["id"]).to eq(user_with_geo.id)
        end

        it "skips users with empty geoinformation" do
          UserCustomField.create!(
            user: non_member_user,
            name: "Geoinformation",
            value: ""
          )

          get "/vzekc-map/locations.json"
          expect(response.status).to eq(200)

          json = response.parsed_body
          expect(json["locations"].length).to eq(1)
        end
      end
    end

    context "when plugin is disabled" do
      before do
        SiteSetting.vzekc_map_enabled = false
        sign_in(member_user)
      end

      it "returns 404" do
        get "/vzekc-map/locations.json"
        expect(response.status).to eq(404)
      end
    end

    context "when members group setting is blank" do
      before do
        SiteSetting.vzekc_map_members_group_name = ""
        sign_in(non_member_user)
      end

      it "allows any logged-in user" do
        get "/vzekc-map/locations.json"
        expect(response.status).to eq(200)
      end
    end
  end
end
