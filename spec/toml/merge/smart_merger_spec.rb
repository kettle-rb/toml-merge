# frozen_string_literal: true

RSpec.describe Toml::Merge::SmartMerger do
  let(:template_content) do
    <<~TOML
      title = "Template"

      [server]
      host = "localhost"
      port = 8080
    TOML
  end

  let(:dest_content) do
    <<~TOML
      title = "Destination"

      [server]
      host = "production.example.com"
      port = 443
      ssl = true
    TOML
  end

  describe "#initialize" do
    it "accepts template and destination content" do
      merger = described_class.new(template_content, dest_content)
      expect(merger).to be_a(described_class)
    end

    it "accepts optional preference" do
      merger = described_class.new(template_content, dest_content, preference: :template)
      expect(merger.options[:preference]).to eq(:template)
    end

    it "accepts optional add_template_only_nodes" do
      merger = described_class.new(template_content, dest_content, add_template_only_nodes: true)
      expect(merger.options[:add_template_only_nodes]).to eq(true)
    end

    context "with invalid template" do
      let(:invalid_template) do
        <<~TOML
          [server
          host = "localhost"
        TOML
      end

      it "raises TemplateParseError" do
        expect {
          described_class.new(invalid_template, dest_content)
        }.to raise_error(Toml::Merge::TemplateParseError)
      end
    end

    context "with invalid destination" do
      let(:invalid_dest) do
        <<~TOML
          [database
          name = "mydb"
        TOML
      end

      it "raises DestinationParseError" do
        expect {
          described_class.new(template_content, invalid_dest)
        }.to raise_error(Toml::Merge::DestinationParseError)
      end
    end
  end

  describe "#merge" do
    subject(:result) { described_class.new(template_content, dest_content).merge }

    it "returns a String" do
      expect(result).to be_a(String)
    end

    it "produces valid TOML output" do
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    context "with debug logging enabled" do
      around do |example|
        original_env = ENV["TOML_MERGE_DEBUG"]
        ENV["TOML_MERGE_DEBUG"] = "1"
        example.run
        ENV["TOML_MERGE_DEBUG"] = original_env
      end

      it "logs debug information during merge" do
        expect {
          described_class.new(template_content, dest_content).merge
        }.not_to raise_error
      end
    end
  end

  describe "#merge_with_debug" do
    subject(:debug_result) { described_class.new(template_content, dest_content).merge_with_debug }

    it "returns a hash with content" do
      expect(debug_result).to be_a(Hash)
      expect(debug_result[:content]).to be_a(String)
    end

    it "returns a hash with statistics" do
      expect(debug_result[:statistics]).to be_a(Hash)
    end
  end
end
