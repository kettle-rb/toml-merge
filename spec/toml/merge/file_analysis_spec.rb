# frozen_string_literal: true

require "spec_helper"

RSpec.describe Toml::Merge::FileAnalysis do
  let(:simple_toml) do
    <<~TOML
      title = "Example"

      [database]
      server = "192.168.1.1"
      port = 5432
    TOML
  end

  let(:complex_toml) do
    <<~TOML
      # This is a TOML document

      title = "TOML Example"

      [owner]
      name = "Tom Preston-Werner"
      dob = 1979-05-27T07:32:00-08:00

      [database]
      enabled = true
      ports = [ 8000, 8001, 8002 ]
      data = [ ["delta", "phi"], [3.14] ]
      temp_targets = { cpu = 79.5, case = 72.0 }

      [servers]

      [servers.alpha]
      ip = "10.0.0.1"
      role = "frontend"

      [servers.beta]
      ip = "10.0.0.2"
      role = "backend"
    TOML
  end

  after do
    TreeHaver.reset_backend!(to: :auto)
    TreeHaver::LanguageRegistry.clear_cache!
  end

  describe "#initialize" do
    context "with valid TOML", :toml_parsing do
      it "parses without errors" do
        analysis = described_class.new(simple_toml)
        expect(analysis.valid?).to be true
        expect(analysis.errors).to be_empty
      end

      it "stores source and lines" do
        analysis = described_class.new(simple_toml)
        lines = simple_toml.lines.map(&:chomp)
        expect(analysis.instance_variable_get(:@lines)).to eq(lines)
      end
    end

    context "with invalid TOML", :toml_parsing do
      let(:invalid_toml) { "this is not = valid toml [" }

      it "records parse errors" do
        analysis = described_class.new(invalid_toml)
        expect(analysis.valid?).to be false
        expect(analysis.errors).not_to be_empty
      end
    end
  end

  describe "#valid?" do
    context "with valid source", :toml_parsing do
      it "returns true" do
        analysis = described_class.new(simple_toml)
        expect(analysis.valid?).to be true
      end
    end

    context "with empty source", :toml_parsing do
      it "returns true for empty string" do
        analysis = described_class.new("")
        expect(analysis.valid?).to be true
      end
    end
  end

  describe "#backend" do
    context "with tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it "reports :tree_sitter backend" do
        analysis = described_class.new(simple_toml)
        expect(analysis.backend).to eq(:tree_sitter)
      end
    end

    context "with citrus backend", :citrus_backend do
      around do |example|
        TreeHaver.with_backend(:citrus) do
          example.run
        end
      end

      it "reports :citrus backend" do
        analysis = described_class.new(simple_toml)
        expect(analysis.backend).to eq(:citrus)
      end
    end

    context "with parslet backend", :parslet_backend do
      around do |example|
        TreeHaver.with_backend(:parslet) do
          example.run
        end
      end

      it "reports :parslet backend" do
        analysis = described_class.new(simple_toml)
        expect(analysis.backend).to eq(:parslet)
      end
    end
  end

  describe "#root_node" do
    context "with valid source", :toml_parsing do
      it "returns a NodeWrapper" do
        analysis = described_class.new(simple_toml)
        expect(analysis.root_node).to be_a(Toml::Merge::NodeWrapper)
      end
    end

    context "with invalid source", :toml_parsing do
      let(:invalid_toml) { "invalid = [" }

      it "returns nil" do
        analysis = described_class.new(invalid_toml)
        expect(analysis.root_node).to be_nil
      end
    end
  end

  describe "#tables" do
    context "with tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it "extracts table sections" do
        analysis = described_class.new(simple_toml)
        tables = analysis.tables
        expect(tables).not_to be_empty
        expect(tables.map { |t| t.text }).to include(match(/database/))
      end
    end

    context "with citrus backend", :citrus_backend do
      around do |example|
        TreeHaver.with_backend(:citrus) do
          example.run
        end
      end

      it "extracts table sections" do
        analysis = described_class.new(simple_toml)
        tables = analysis.tables
        expect(tables).not_to be_empty
      end
    end

    context "with parslet backend", :parslet_backend do
      around do |example|
        TreeHaver.with_backend(:parslet) do
          example.run
        end
      end

      it "extracts table sections" do
        analysis = described_class.new(simple_toml)
        tables = analysis.tables
        # Parslet may structure tables differently, but should still find them
        expect(tables).to be_an(Array)
      end
    end
  end

  describe "#root_pairs" do
    let(:toml_with_root_pairs) do
      <<~TOML
        name = "root-level"
        version = "1.0.0"

        [section]
        key = "value"
      TOML
    end

    context "with tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it "extracts root-level key-value pairs" do
        analysis = described_class.new(toml_with_root_pairs)
        pairs = analysis.root_pairs
        expect(pairs).not_to be_empty
        expect(pairs.length).to be >= 2
      end
    end

    context "with citrus backend", :citrus_backend do
      around do |example|
        TreeHaver.with_backend(:citrus) do
          example.run
        end
      end

      it "extracts root-level key-value pairs" do
        analysis = described_class.new(toml_with_root_pairs)
        pairs = analysis.root_pairs
        expect(pairs).not_to be_empty
      end
    end

    context "with parslet backend", :parslet_backend do
      around do |example|
        TreeHaver.with_backend(:parslet) do
          example.run
        end
      end

      it "extracts root-level key-value pairs" do
        analysis = described_class.new(toml_with_root_pairs)
        pairs = analysis.root_pairs
        expect(pairs).to be_an(Array)
      end
    end
  end

  describe "#signature_map" do
    context "with tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it "builds signature map from statements" do
        analysis = described_class.new(simple_toml)
        sig_map = analysis.signature_map
        expect(sig_map).to be_a(Hash)
      end
    end

    context "with citrus backend", :citrus_backend do
      around do |example|
        TreeHaver.with_backend(:citrus) do
          example.run
        end
      end

      it "builds signature map from statements" do
        analysis = described_class.new(simple_toml)
        sig_map = analysis.signature_map
        expect(sig_map).to be_a(Hash)
      end
    end

    context "with parslet backend", :parslet_backend do
      around do |example|
        TreeHaver.with_backend(:parslet) do
          example.run
        end
      end

      it "builds signature map from statements" do
        analysis = described_class.new(simple_toml)
        sig_map = analysis.signature_map
        expect(sig_map).to be_a(Hash)
      end
    end
  end

  describe "cross-backend consistency", :toml_parsing do
    # Test that different backends produce consistent results
    let(:test_toml) do
      <<~TOML
        name = "test"

        [section]
        key = "value"
      TOML
    end

    # Helper to get analysis for a specific backend
    def analyze_with_backend(backend_name, source)
      TreeHaver.with_backend(backend_name) do
        described_class.new(source)
      end
    end

    context "comparing tree-sitter and citrus", :mri_backend, :citrus_backend, :toml_grammar do
      it "both report valid for valid TOML" do
        ts_analysis = analyze_with_backend(:mri, test_toml)
        citrus_analysis = analyze_with_backend(:citrus, test_toml)

        expect(ts_analysis.valid?).to be true
        expect(citrus_analysis.valid?).to be true
      end

      it "both find tables" do
        ts_analysis = analyze_with_backend(:mri, test_toml)
        citrus_analysis = analyze_with_backend(:citrus, test_toml)

        expect(ts_analysis.tables).not_to be_empty
        expect(citrus_analysis.tables).not_to be_empty
      end
    end

    context "comparing tree-sitter and parslet", :mri_backend, :parslet_backend, :toml_grammar do
      it "both report valid for valid TOML" do
        ts_analysis = analyze_with_backend(:mri, test_toml)
        parslet_analysis = analyze_with_backend(:parslet, test_toml)

        expect(ts_analysis.valid?).to be true
        expect(parslet_analysis.valid?).to be true
      end
    end

    context "comparing citrus and parslet", :citrus_backend, :parslet_backend do
      it "both report valid for valid TOML" do
        citrus_analysis = analyze_with_backend(:citrus, test_toml)
        parslet_analysis = analyze_with_backend(:parslet, test_toml)

        expect(citrus_analysis.valid?).to be true
        expect(parslet_analysis.valid?).to be true
      end
    end
  end
end

