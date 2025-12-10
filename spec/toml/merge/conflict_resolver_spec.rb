# frozen_string_literal: true

RSpec.describe Toml::Merge::ConflictResolver do
  # ConflictResolver requires real FileAnalysis objects with parsed content
  # These tests document the expected interface

  let(:template_content) do
    <<~TOML
      [server]
      host = "localhost"
      port = 8080
    TOML
  end

  let(:dest_content) do
    <<~TOML
      [server]
      host = "production.example.com"
      port = 443
      ssl = true
    TOML
  end

  describe "#initialize" do
    it "accepts template and destination analyses" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      expect(resolver).to be_a(described_class)
    end
  end

  describe "#resolve" do
    it "populates the result with merged content" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end
  end
end
