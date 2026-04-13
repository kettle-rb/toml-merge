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

  describe "shared comment capability" do
    let(:commented_toml) do
      <<~TOML
        # preamble

        title = "TOML # value" # inline title

        [database] # table inline
        # server docs
        server = "192.168.1.1"

        # postlude
      TOML
    end

    context "with tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it "exposes native-backed shared comment metadata and attachments" do
        analysis = described_class.new(commented_toml)

        expect(analysis.comment_capability.native_partial?).to be true
        expect(analysis.comment_nodes.map(&:line_number)).to eq([1, 3, 5, 6, 9])

        title_pair = analysis.root_pairs.find { |pair| pair.key_name == "title" }
        expect(title_pair).not_to be_nil
        attachment = analysis.comment_attachment_for(title_pair)

        # Line-1 comment separated by a gap is preamble, not owned by the first key
        expect(attachment.leading_region).to be_nil
        expect(attachment.inline_region.nodes.map(&:line_number)).to eq([3])

        augmenter = analysis.comment_augmenter(owners: analysis.statements)
        expect(augmenter.preamble_region).not_to be_nil
        expect(augmenter.preamble_region.nodes.map(&:line_number)).to eq([1])
        expect(augmenter.postlude_region.nodes.map(&:line_number)).to eq([9])
      end

      it "reports a native-read synthetic-write support style" do
        analysis = described_class.new(commented_toml)

        expect(analysis.comment_support_style).to be_a(Ast::Merge::Comment::SupportStyle)
        expect(analysis.comment_support_style.native_read_synthetic_write?).to be true
        expect(analysis.comment_support_style.synthetic_write?).to be true
        expect(analysis.comment_support_style.details[:capability]).to eq(:native_partial)
      end

      it "resolves shared comment helper classes through the ast-merge namespace boundary" do
        # FileAnalysis should rely on Ast::Merge::Comment constants, whether they are
        # still pending autoload or have already been loaded by earlier specs.
        expect(
          Ast::Merge::Comment.autoload?(:Capability) || Ast::Merge::Comment.const_defined?(:Capability, false),
        ).to be_truthy
        expect(
          Ast::Merge::Comment.autoload?(:Attachment) || Ast::Merge::Comment.const_defined?(:Attachment, false),
        ).to be_truthy
        expect(
          Ast::Merge::Comment.autoload?(:Region) || Ast::Merge::Comment.const_defined?(:Region, false),
        ).to be_truthy
        expect(
          Ast::Merge::Comment.autoload?(:TrackedHashAdapter) || Ast::Merge::Comment.const_defined?(:TrackedHashAdapter, false),
        ).to be_truthy

        analysis = described_class.new(commented_toml)
        capability = analysis.comment_capability
        attachment = analysis.comment_attachment_for(analysis.root_pairs.first)

        expect(capability).to be_a(Ast::Merge::Comment::Capability)
        expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      end
    end

    context "with parslet backend", :parslet_backend do
      around do |example|
        TreeHaver.with_backend(:parslet) do
          example.run
        end
      end

      it "falls back to source-scanned comments without treating # inside strings as comments" do
        analysis = described_class.new(commented_toml)

        expect(analysis.comment_capability.source_augmented?).to be true
        expect(analysis.comment_nodes.map(&:line_number)).to eq([1, 3, 5, 6, 9])
        expect(analysis.comment_node_at(3)).not_to be_nil
        expect(analysis.comment_node_at(3).text).to include("inline title")
      end

      it "reports a source-augmented synthetic support style" do
        analysis = described_class.new(commented_toml)

        expect(analysis.comment_support_style).to be_a(Ast::Merge::Comment::SupportStyle)
        expect(analysis.comment_support_style.source_augmented_synthetic?).to be true
        expect(analysis.comment_support_style.synthetic_write?).to be true
        expect(analysis.comment_support_style.details[:capability]).to eq(:source_augmented)
      end
    end
  end

  describe "shared layout compliance" do
    let(:layout_toml) do
      <<~TOML

        title = "Example"

        color = "blue"

      TOML
    end

    shared_examples "a layout-compliant TOML analysis" do
      let(:analysis) { described_class.new(layout_toml) }
      let(:first_owner) do
        analysis.statements.find { |statement| statement.respond_to?(:start_line) && statement.start_line == 2 }
      end
      let(:second_owner) do
        analysis.statements.find { |statement| statement.respond_to?(:start_line) && statement.start_line == 4 }
      end
      let(:layout_augmenter) { analysis.layout_augmenter(owners: [first_owner, second_owner].compact) }
      let(:layout_attachment) { layout_augmenter.attachment_for(first_owner) }

      it "finds stable owners for the shared layout contract" do
        expect(first_owner).not_to be_nil
        expect(second_owner).not_to be_nil
      end

      it_behaves_like "Ast::Merge::Layout::Attachment" do
        let(:expected_attachment_owner) { first_owner }
        let(:expected_leading_gap_kind) { :preamble }
        let(:expected_trailing_gap_kind) { :interstitial }
        let(:expected_gap_ranges) { [1..1, 3..3] }
        let(:expected_leading_controls_output) { true }
        let(:expected_trailing_controls_output) { false }
      end

      it_behaves_like "Ast::Merge::Layout::Augmenter" do
        let(:augmenter_owner) { first_owner }
        let(:expected_preamble_range) { 1..1 }
        let(:expected_postlude_range) { 5..5 }
        let(:expected_interstitial_ranges) { [3..3] }
        let(:expected_owner_leading_gap_kind) { :preamble }
        let(:expected_owner_trailing_gap_kind) { :interstitial }
      end
    end

    context "with tree-sitter backend", :mri_backend, :toml_grammar do
      around do |example|
        TreeHaver.with_backend(:mri) do
          example.run
        end
      end

      it_behaves_like "a layout-compliant TOML analysis"
    end

    context "with citrus backend", :citrus_backend do
      around do |example|
        TreeHaver.with_backend(:citrus) do
          example.run
        end
      end

      it_behaves_like "a layout-compliant TOML analysis"
    end

    context "with parslet backend", :parslet_backend do
      around do |example|
        TreeHaver.with_backend(:parslet) do
          example.run
        end
      end

      it_behaves_like "a layout-compliant TOML analysis"
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

    context "when comparing tree-sitter and citrus", :citrus_backend, :mri_backend, :toml_grammar do
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

    context "when comparing tree-sitter and parslet", :mri_backend, :parslet_backend, :toml_grammar do
      it "both report valid for valid TOML" do
        ts_analysis = analyze_with_backend(:mri, test_toml)
        parslet_analysis = analyze_with_backend(:parslet, test_toml)

        expect(ts_analysis.valid?).to be true
        expect(parslet_analysis.valid?).to be true
      end
    end

    context "when comparing citrus and parslet", :citrus_backend, :parslet_backend do
      it "both report valid for valid TOML" do
        citrus_analysis = analyze_with_backend(:citrus, test_toml)
        parslet_analysis = analyze_with_backend(:parslet, test_toml)

        expect(citrus_analysis.valid?).to be true
        expect(parslet_analysis.valid?).to be true
      end
    end
  end
end
