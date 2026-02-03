# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcMap::GeoParser do
  describe ".parse" do
    context "with geo: URI format" do
      it "parses geo:lat,lng?z=zoom format" do
        result = described_class.parse("geo:52.535150,13.394236?z=19")
        expect(result).to eq([{ lat: 52.535150, lng: 13.394236, zoom: 19 }])
      end

      it "parses geo:lat,lng format without zoom" do
        result = described_class.parse("geo:50.800411,6.914046")
        expect(result).to eq([{ lat: 50.800411, lng: 6.914046, zoom: nil }])
      end

      it "parses geo: lat,lng format with space after colon" do
        result = described_class.parse("geo: 49.536401,8.350006")
        expect(result).to eq([{ lat: 49.536401, lng: 8.350006, zoom: nil }])
      end

      it "handles space around comma in coordinates" do
        result = described_class.parse("geo:52.535150, 13.394236")
        expect(result).to eq([{ lat: 52.535150, lng: 13.394236, zoom: nil }])
      end
    end

    context "with typos" do
      it "parses eo: typo (missing g)" do
        result = described_class.parse("eo:52.535150,13.394236")
        expect(result).to eq([{ lat: 52.535150, lng: 13.394236, zoom: nil }])
      end

      it "parses Geo: with capital G" do
        result = described_class.parse("Geo:52.535150,13.394236")
        expect(result).to eq([{ lat: 52.535150, lng: 13.394236, zoom: nil }])
      end

      it "parses GEO: all caps" do
        result = described_class.parse("GEO:52.535150,13.394236?z=10")
        expect(result).to eq([{ lat: 52.535150, lng: 13.394236, zoom: 10 }])
      end
    end

    context "with raw coordinates" do
      it "parses raw lat,lng format" do
        result = described_class.parse("50.554224,9.676251")
        expect(result).to eq([{ lat: 50.554224, lng: 9.676251, zoom: nil }])
      end

      it "parses negative coordinates" do
        result = described_class.parse("-33.8688,151.2093")
        expect(result).to eq([{ lat: -33.8688, lng: 151.2093, zoom: nil }])
      end

      it "parses coordinates with negative longitude" do
        result = described_class.parse("40.7128,-74.0060")
        expect(result).to eq([{ lat: 40.7128, lng: -74.0060, zoom: nil }])
      end
    end

    context "with OpenStreetMap URLs" do
      it "parses standard OSM URL format" do
        result = described_class.parse("https://www.openstreetmap.org/?#map=19/52.129158/11.604304")
        expect(result).to eq([{ lat: 52.129158, lng: 11.604304, zoom: 19 }])
      end

      it "parses OSM URL with different zoom level" do
        result = described_class.parse("https://www.openstreetmap.org/#map=15/48.8566/2.3522")
        expect(result).to eq([{ lat: 48.8566, lng: 2.3522, zoom: 15 }])
      end

      it "parses OSM URL with negative coordinates" do
        result = described_class.parse("https://www.openstreetmap.org/#map=12/-33.8688/151.2093")
        expect(result).to eq([{ lat: -33.8688, lng: 151.2093, zoom: 12 }])
      end
    end

    context "with multiple locations" do
      it "parses space-separated geo: URIs" do
        result = described_class.parse("geo:48.886,9.126 geo:48.774,9.239")
        expect(result).to eq([
          { lat: 48.886, lng: 9.126, zoom: nil },
          { lat: 48.774, lng: 9.239, zoom: nil }
        ])
      end

      it "parses mixed format locations" do
        result = described_class.parse("geo:52.520,13.405?z=15 50.110,8.682")
        expect(result).to eq([
          { lat: 52.520, lng: 13.405, zoom: 15 },
          { lat: 50.110, lng: 8.682, zoom: nil }
        ])
      end

      it "parses multiple OSM URLs" do
        input = "https://www.openstreetmap.org/#map=10/52.52/13.40 https://www.openstreetmap.org/#map=12/48.85/2.35"
        result = described_class.parse(input)
        expect(result).to eq([
          { lat: 52.52, lng: 13.40, zoom: 10 },
          { lat: 48.85, lng: 2.35, zoom: 12 }
        ])
      end
    end

    context "with invalid input" do
      it "returns empty array for nil" do
        expect(described_class.parse(nil)).to eq([])
      end

      it "returns empty array for empty string" do
        expect(described_class.parse("")).to eq([])
      end

      it "returns empty array for whitespace only" do
        expect(described_class.parse("   ")).to eq([])
      end

      it "returns empty array for invalid format" do
        expect(described_class.parse("not a coordinate")).to eq([])
      end

      it "returns empty array for incomplete geo URI" do
        expect(described_class.parse("geo:")).to eq([])
      end

      it "returns empty array for invalid latitude (> 90)" do
        expect(described_class.parse("geo:95.0,13.0")).to eq([])
      end

      it "returns empty array for invalid latitude (< -90)" do
        expect(described_class.parse("geo:-95.0,13.0")).to eq([])
      end

      it "returns empty array for invalid longitude (> 180)" do
        expect(described_class.parse("geo:52.0,185.0")).to eq([])
      end

      it "returns empty array for invalid longitude (< -180)" do
        expect(described_class.parse("geo:52.0,-185.0")).to eq([])
      end
    end

    context "with edge cases" do
      it "handles coordinates at origin" do
        result = described_class.parse("geo:0,0")
        expect(result).to eq([{ lat: 0.0, lng: 0.0, zoom: nil }])
      end

      it "handles coordinates at max bounds" do
        result = described_class.parse("geo:90,180")
        expect(result).to eq([{ lat: 90.0, lng: 180.0, zoom: nil }])
      end

      it "handles coordinates at min bounds" do
        result = described_class.parse("geo:-90,-180")
        expect(result).to eq([{ lat: -90.0, lng: -180.0, zoom: nil }])
      end

      it "handles integer coordinates" do
        result = described_class.parse("52,13")
        expect(result).to eq([{ lat: 52.0, lng: 13.0, zoom: nil }])
      end

      it "handles extra whitespace around input" do
        result = described_class.parse("  geo:52.52,13.40  ")
        expect(result).to eq([{ lat: 52.52, lng: 13.40, zoom: nil }])
      end

      it "filters out invalid entries in mixed input" do
        result = described_class.parse("geo:52.52,13.40 invalid geo:48.85,2.35")
        expect(result).to eq([
          { lat: 52.52, lng: 13.40, zoom: nil },
          { lat: 48.85, lng: 2.35, zoom: nil }
        ])
      end
    end

    context "with real-world examples from PLAN.md" do
      it "parses Berlin example" do
        result = described_class.parse("geo:52.535150,13.394236?z=19")
        expect(result.first[:lat]).to be_within(0.0001).of(52.5351)
        expect(result.first[:lng]).to be_within(0.0001).of(13.3942)
        expect(result.first[:zoom]).to eq(19)
      end

      it "parses Cologne example" do
        result = described_class.parse("geo:50.800411,6.914046")
        expect(result.first[:lat]).to be_within(0.0001).of(50.8004)
        expect(result.first[:lng]).to be_within(0.0001).of(6.9140)
      end

      it "parses Mannheim example with space" do
        result = described_class.parse("geo: 49.536401,8.350006")
        expect(result.first[:lat]).to be_within(0.0001).of(49.5364)
        expect(result.first[:lng]).to be_within(0.0001).of(8.3500)
      end

      it "parses Fulda raw example" do
        result = described_class.parse("50.554224,9.676251")
        expect(result.first[:lat]).to be_within(0.0001).of(50.5542)
        expect(result.first[:lng]).to be_within(0.0001).of(9.6762)
      end

      it "parses Magdeburg OSM example" do
        result = described_class.parse("https://www.openstreetmap.org/?#map=19/52.129158/11.604304")
        expect(result.first[:lat]).to be_within(0.0001).of(52.1291)
        expect(result.first[:lng]).to be_within(0.0001).of(11.6043)
        expect(result.first[:zoom]).to eq(19)
      end
    end
  end
end
