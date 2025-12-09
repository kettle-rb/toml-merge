# frozen_string_literal: true

RSpec.describe "TOML Smart Merge Integration" do
  let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

  describe "merging template and destination files" do
    let(:template_path) { File.join(fixtures_path, "template.toml") }
    let(:destination_path) { File.join(fixtures_path, "destination.toml") }
    let(:template) { File.read(template_path) }
    let(:destination) { File.read(destination_path) }

    subject(:merger) { Toml::Merge::SmartMerger.new(template, destination) }

    it "produces valid merged output" do
      result = merger.merge
      expect(result.content).to be_a(String)
      expect(result.content).not_to be_empty
    end

    it "preserves destination-only sections" do
      result = merger.merge
      # The destination has a [cache] section not in template
      expect(result.content).to include("cache")
    end

    it "preserves destination values for matching keys" do
      result = merger.merge
      # Destination has host = "production.example.com"
      expect(result.content).to include("production.example.com")
    end

    context "with add_template_only_nodes enabled" do
      subject(:merger) do
        Toml::Merge::SmartMerger.new(
          template,
          destination,
          add_template_only_nodes: true,
        )
      end

      it "includes template-only sections" do
        result = merger.merge
        # Template has [logging] section not in destination
        expect(result.content).to include("logging")
      end
    end
  end

  describe "error handling" do
    let(:invalid_toml) { File.read(File.join(fixtures_path, "invalid.toml")) }
    let(:valid_toml) { "title = \"Valid\"\n" }

    it "raises TemplateParseError for invalid template" do
      expect {
        Toml::Merge::SmartMerger.new(invalid_toml, valid_toml)
      }.to raise_error(Toml::Merge::TemplateParseError)
    end

    it "raises DestinationParseError for invalid destination" do
      expect {
        Toml::Merge::SmartMerger.new(valid_toml, invalid_toml)
      }.to raise_error(Toml::Merge::DestinationParseError)
    end
  end
end
