# frozen_string_literal: true

RSpec.describe Toml::Merge::FileAnalysis do
  let(:valid_toml) do
    <<~TOML
      title = "My App"

      [server]
      host = "localhost"
      port = 8080

      [database]
      name = "mydb"
      host = "localhost"
    TOML
  end

  let(:invalid_toml) do
    <<~TOML
      [server
      host = "localhost"
    TOML
  end

  describe "#initialize" do
    context "with valid TOML" do
      subject(:analysis) { described_class.new(valid_toml) }

      it "parses successfully" do
        expect(analysis).to be_a(described_class)
      end

      it "is valid" do
        expect(analysis.valid?).to be true
      end

      it "has no errors" do
        expect(analysis.errors).to be_empty
      end
    end

    context "with invalid TOML" do
      subject(:analysis) { described_class.new(invalid_toml) }

      it "creates analysis object" do
        expect(analysis).to be_a(described_class)
      end

      it "is invalid" do
        expect(analysis.valid?).to be false
      end

      it "has errors" do
        expect(analysis.errors).not_to be_empty
      end
    end
  end

  describe "#root_node" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns a NodeWrapper" do
      expect(analysis.root_node).to be_a(Toml::Merge::NodeWrapper)
    end
  end

  describe "#lines" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns source lines" do
      expect(analysis.lines).to be_an(Array)
      expect(analysis.lines.first).to eq('title = "My App"')
    end
  end

  describe "#signature_map" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns a hash mapping signatures to nodes" do
      expect(analysis.signature_map).to be_a(Hash)
    end

    it "contains entries for tables" do
      # Should have entries for server and database tables
      signatures = analysis.signature_map.keys
      expect(signatures.any? { |s| s.include?("server") }).to be true
      expect(signatures.any? { |s| s.include?("database") }).to be true
    end
  end
end
