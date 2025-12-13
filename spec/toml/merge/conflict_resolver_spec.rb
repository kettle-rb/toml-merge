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

    it "handles preference :template" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :template,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end

    it "handles add_template_only_nodes: true" do
      template_content_with_extra = <<~TOML
        [server]
        host = "localhost"
        port = 8080

        [database]
        url = "sqlite://db.sqlite"
      TOML

      dest_content_minimal = <<~TOML
        [server]
        host = "production.example.com"
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_content_with_extra)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content_minimal)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: true,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
      expect(result.content).to include("[database]")
    end

    it "merges array nodes" do
      template_with_array = <<~TOML
        items = [1, 2, 3]
      TOML

      dest_with_array = <<~TOML
        items = [4, 5, 6]
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_with_array)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_with_array)
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

    it "merges array nodes" do
      template_with_array = <<~TOML
        items = [1, 2, 3]
      TOML

      dest_with_array = <<~TOML
        items = [4, 5, 6]
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_with_array)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_with_array)
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

    it "merges inline table nodes" do
      template_with_inline = <<~TOML
        config = { a = 1, b = 2 }
      TOML

      dest_with_inline = <<~TOML
        config = { a = 10, c = 3 }
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_with_inline)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_with_inline)
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

    it "handles matching node signatures" do
      # Create TOML where both have the same table name
      template_toml = <<~TOML
        [server]
        host = "template.example.com"
        port = 8080
      TOML

      dest_toml = <<~TOML
        [server]
        host = "dest.example.com"
        ssl = true
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: true,
      )

      resolver.resolve(result)

      expect(result.content).to include("[server]")
      expect(result.content).to include("host = \"dest.example.com\"") # destination preferred
      expect(result.content).to include("port = 8080") # from template
      expect(result.content).to include("ssl = true") # from destination
    end
  end
end
