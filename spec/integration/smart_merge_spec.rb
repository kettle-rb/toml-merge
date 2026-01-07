# frozen_string_literal: true

RSpec.describe "TOML Smart Merge Integration" do
  let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

  describe "merging template and destination files" do
    subject(:merger) { Toml::Merge::SmartMerger.new(template, destination) }

    let(:template_path) { File.join(fixtures_path, "template.toml") }
    let(:destination_path) { File.join(fixtures_path, "destination.toml") }
    let(:template) { File.read(template_path) }
    let(:destination) { File.read(destination_path) }

    it "produces valid merged output" do
      result = merger.merge
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "preserves destination-only sections" do
      result = merger.merge
      # The destination has a [cache] section not in template
      expect(result).to include("cache")
    end

    it "preserves destination values for matching keys" do
      result = merger.merge
      # Destination has host = "production.example.com"
      expect(result).to include("production.example.com")
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
        expect(result).to include("logging")
      end
    end
  end

  describe "error handling" do
    let(:invalid_toml) { File.read(File.join(fixtures_path, "invalid.toml")) }
    let(:valid_toml) { "title = \"Valid\"\n" }

    # Shared examples for invalid TOML error detection
    shared_examples "raises TemplateParseError for invalid template" do
      it "raises TemplateParseError for invalid template" do
        expect {
          Toml::Merge::SmartMerger.new(invalid_toml, valid_toml)
        }.to raise_error(Toml::Merge::TemplateParseError)
      end
    end

    shared_examples "raises DestinationParseError for invalid destination" do
      it "raises DestinationParseError for invalid destination" do
        expect {
          Toml::Merge::SmartMerger.new(valid_toml, invalid_toml)
        }.to raise_error(Toml::Merge::DestinationParseError)
      end
    end

    # Test error handling with :auto backend (uses whatever is available)
    # This tests the default behavior most users will experience
    context "with :auto backend", :toml_parsing do
      around do |example|
        original_backend = TreeHaver.backend
        begin
          TreeHaver.backend = :auto
          example.run
        ensure
          TreeHaver.backend = original_backend
        end
      end

      it_behaves_like "raises TemplateParseError for invalid template"
      it_behaves_like "raises DestinationParseError for invalid destination"
    end

    # Test error handling with explicit tree-sitter backend
    # This ensures native parsing correctly detects errors
    # Uses :mri_backend tag because this context explicitly uses TreeHaver.with_backend(:mri)
    context "with explicit tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        # Use :mri to explicitly request tree-sitter (not :auto)
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it_behaves_like "raises TemplateParseError for invalid template"
      it_behaves_like "raises DestinationParseError for invalid destination"
    end

    # Test error handling with explicit Citrus backend
    context "with explicit Citrus backend", :toml_rb do
      around do |example|
        TreeHaver.with_backend(:citrus) do
          example.run
        end
      end

      it_behaves_like "raises TemplateParseError for invalid template"
      it_behaves_like "raises DestinationParseError for invalid destination"
    end

    # Test error handling with explicit Rust backend
    context "with explicit Rust backend", :rust_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:rust) do
          example.run
        end
      end

      it_behaves_like "raises TemplateParseError for invalid template"
      it_behaves_like "raises DestinationParseError for invalid destination"
    end

    # Test error handling with explicit Java backend
    context "with explicit Java backend", :java_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:java) do
          example.run
        end
      end

      it_behaves_like "raises TemplateParseError for invalid template"
      it_behaves_like "raises DestinationParseError for invalid destination"
    end
  end
end
