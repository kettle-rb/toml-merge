# frozen_string_literal: true

# FileAnalysis specs with explicit backend testing
#
# This spec file tests FileAnalysis behavior across both available backends:
# - :tree_sitter (via tree-sitter-toml grammar, tagged :toml_grammar)
# - :citrus (via toml-rb gem, tagged :toml_rb)
#
# We define shared examples that are parameterized, then include them in
# backend-specific contexts that use TreeHaver.with_backend to explicitly
# select the backend under test.

RSpec.describe Toml::Merge::FileAnalysis do
  # ============================================================
  # Shared examples for backend-agnostic behavior
  # These examples take the expected backend symbol as a parameter
  # ============================================================

  shared_examples "valid TOML parsing" do |expected_backend:|
    describe "with valid TOML" do
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

      it "uses the #{expected_backend} backend" do
        expect(analysis.backend).to eq(expected_backend)
      end

      it "returns a NodeWrapper for root_node" do
        expect(analysis.root_node).to be_a(Toml::Merge::NodeWrapper)
      end

      it "returns source lines" do
        expect(analysis.lines).to be_an(Array)
        expect(analysis.lines.first).to eq('title = "My App"')
      end

      it "returns statement nodes excluding comments" do
        statements = analysis.statements
        expect(statements).to be_an(Array)
        expect(statements.all? { |s| s.type != :comment }).to be true
      end
    end
  end

  shared_examples "invalid TOML detection" do
    describe "with invalid TOML" do
      let(:invalid_toml) do
        <<~TOML
          [server
          host = "localhost"
        TOML
      end

      subject(:analysis) { described_class.new(invalid_toml) }

      it "is not valid" do
        expect(analysis.valid?).to be false
      end

      it "has errors" do
        expect(analysis.errors).not_to be_empty
      end
    end
  end

  shared_examples "table parsing" do
    describe "#tables" do
      let(:toml_with_tables) do
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

      subject(:analysis) { described_class.new(toml_with_tables) }

      it "returns table nodes" do
        tables = analysis.tables
        expect(tables).to be_an(Array)
        expect(tables.size).to eq(2) # server and database
      end

      it "returns only table or array_of_tables nodes" do
        tables = analysis.tables
        expect(tables.all? { |t| t.table? || t.array_of_tables? }).to be true
      end
    end
  end

  shared_examples "root pairs extraction" do
    describe "#root_pairs" do
      let(:toml_with_root_pairs) do
        <<~TOML
          title = "My App"

          [server]
          host = "localhost"
          port = 8080
        TOML
      end

      subject(:analysis) { described_class.new(toml_with_root_pairs) }

      it "returns an array of pair NodeWrappers" do
        pairs = analysis.root_pairs
        expect(pairs).to be_an(Array)
        expect(pairs.length).to eq(1) # Only "title" at root level
      end

      it "returns only root-level pairs (not inside tables)" do
        pairs = analysis.root_pairs
        key_names = pairs.map { |p| p.key_name.strip }
        expect(key_names).to include("title")
        expect(key_names).not_to include("host")
        expect(key_names).not_to include("port")
      end

      it "returns key name for pairs" do
        pairs = analysis.root_pairs
        expect(pairs.first.key_name.strip).to eq("title")
      end
    end
  end

  shared_examples "signature generation" do
    describe "#generate_signature" do
      let(:toml_for_signature) do
        <<~TOML
          title = "My App"

          [server]
          host = "localhost"
        TOML
      end

      subject(:analysis) { described_class.new(toml_for_signature) }

      it "generates signature for a table" do
        table = analysis.tables.first
        sig = analysis.generate_signature(table)
        expect(sig).to be_an(Array)
        sig_str = sig.map(&:to_s).join(" ")
        expect(sig_str).to include("server")
      end

      it "generates signature for a pair" do
        pair = analysis.root_pairs.first
        sig = analysis.generate_signature(pair)
        expect(sig).to be_an(Array)
        sig_str = sig.map(&:to_s).join(" ")
        expect(sig_str).to include("title")
      end

      it "returns nil for nil input" do
        sig = analysis.generate_signature(nil)
        expect(sig).to be_nil
      end
    end
  end

  shared_examples "array of tables parsing" do
    describe "with array of tables" do
      let(:array_toml) do
        <<~TOML
          [[servers]]
          name = "alpha"

          [[servers]]
          name = "beta"
        TOML
      end

      subject(:analysis) { described_class.new(array_toml) }

      it "parses array of tables successfully" do
        expect(analysis.valid?).to be true
      end

      it "returns correct number of tables" do
        tables = analysis.tables
        expect(tables.length).to eq(2)
      end

      it "identifies tables as array_of_tables" do
        tables = analysis.tables
        tables.each do |table|
          expect(table.array_of_tables?).to be true
        end
      end
    end
  end

  shared_examples "inline table parsing" do
    describe "with inline tables" do
      let(:inline_toml) do
        <<~TOML
          config = { debug = true, level = 3 }
        TOML
      end

      subject(:analysis) { described_class.new(inline_toml) }

      it "parses inline tables successfully" do
        expect(analysis.valid?).to be true
      end

      it "returns root pairs including inline table" do
        pairs = analysis.root_pairs
        expect(pairs.length).to eq(1)
        expect(pairs.first.key_name.strip).to eq("config")
      end
    end
  end

  shared_examples "signature_map generation" do
    describe "#signature_map" do
      let(:toml_for_sig_map) do
        <<~TOML
          title = "My App"

          [server]
          host = "localhost"
        TOML
      end

      subject(:analysis) { described_class.new(toml_for_sig_map) }

      it "returns a hash mapping signatures to nodes" do
        map = analysis.signature_map
        expect(map).to be_a(Hash)
        expect(map.keys).to all(be_an(Array).or(be_nil))
        expect(map.values).to all(be_a(Toml::Merge::NodeWrapper))
      end
    end
  end

  shared_examples "fallthrough_node? behavior" do
    describe "#fallthrough_node?" do
      let(:simple_toml) { 'title = "My App"' }

      subject(:analysis) { described_class.new(simple_toml) }

      it "returns true for NodeWrapper instances" do
        node_wrapper = analysis.root_node
        expect(analysis.fallthrough_node?(node_wrapper)).to be true
      end

      it "returns false for strings" do
        expect(analysis.fallthrough_node?("string")).to be false
      end

      it "returns false for numbers" do
        expect(analysis.fallthrough_node?(123)).to be false
      end

      it "returns false for nil" do
        expect(analysis.fallthrough_node?(nil)).to be false
      end
    end
  end

  shared_examples "line_at access" do
    describe "#line_at" do
      let(:multiline_toml) do
        <<~TOML
          title = "My App"

          [server]
          host = "localhost"
        TOML
      end

      subject(:analysis) { described_class.new(multiline_toml) }

      it "returns line at valid index (1-based)" do
        line = analysis.line_at(1)
        expect(line).to eq('title = "My App"')
      end

      it "returns nil for invalid index" do
        line = analysis.line_at(100)
        expect(line).to be_nil
      end

      it "returns nil for zero index" do
        line = analysis.line_at(0)
        expect(line).to be_nil
      end
    end
  end

  # ============================================================
  # :auto backend tests (uses whatever is available)
  # This tests the default behavior most users will experience
  # ============================================================

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

    # With :auto, we don't know which backend will be used, so we can't
    # assert the specific backend. We test that it works regardless.
    describe "with valid TOML" do
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

      it "uses either :tree_sitter or :citrus backend" do
        expect(analysis.backend).to eq(:tree_sitter).or eq(:citrus)
      end
    end

    include_examples "invalid TOML detection"
    include_examples "table parsing"
    include_examples "root pairs extraction"
    include_examples "signature generation"
    include_examples "array of tables parsing"
    include_examples "inline table parsing"
    include_examples "signature_map generation"
    include_examples "fallthrough_node? behavior"
    include_examples "line_at access"
  end

  # ============================================================
  # Explicit tree-sitter backend tests (native grammar)
  # ============================================================

  context "with explicit tree-sitter backend", :toml_grammar do
    around do |example|
      # Use :mri to explicitly request tree-sitter (not :auto)
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    include_examples "valid TOML parsing", expected_backend: :tree_sitter
    include_examples "invalid TOML detection"
    include_examples "table parsing"
    include_examples "root pairs extraction"
    include_examples "signature generation"
    include_examples "array of tables parsing"
    include_examples "inline table parsing"
    include_examples "signature_map generation"
    include_examples "fallthrough_node? behavior"
    include_examples "line_at access"
  end

  # ============================================================
  # Explicit Citrus backend tests (toml-rb)
  # ============================================================

  context "with explicit Citrus backend", :toml_rb do
    around do |example|
      TreeHaver.with_backend(:citrus) do
        example.run
      end
    end

    include_examples "valid TOML parsing", expected_backend: :citrus
    include_examples "invalid TOML detection"
    include_examples "table parsing"
    include_examples "root pairs extraction"
    include_examples "signature generation"
    include_examples "array of tables parsing"
    include_examples "inline table parsing"
    include_examples "signature_map generation"
    include_examples "fallthrough_node? behavior"
    include_examples "line_at access"
  end

  # ============================================================
  # Explicit Rust backend tests (tree-sitter via rust bindings)
  # ============================================================

  context "with explicit Rust backend", :rust_backend, :toml_grammar do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    include_examples "valid TOML parsing", expected_backend: :tree_sitter
    include_examples "invalid TOML detection"
    include_examples "table parsing"
    include_examples "root pairs extraction"
    include_examples "signature generation"
    include_examples "array of tables parsing"
    include_examples "inline table parsing"
    include_examples "signature_map generation"
    include_examples "fallthrough_node? behavior"
    include_examples "line_at access"
  end

  # ============================================================
  # Explicit Java backend tests (tree-sitter via java bindings)
  # ============================================================

  context "with explicit Java backend", :java_backend, :toml_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    include_examples "valid TOML parsing", expected_backend: :tree_sitter
    include_examples "invalid TOML detection"
    include_examples "table parsing"
    include_examples "root pairs extraction"
    include_examples "signature generation"
    include_examples "array of tables parsing"
    include_examples "inline table parsing"
    include_examples "signature_map generation"
    include_examples "fallthrough_node? behavior"
    include_examples "line_at access"
  end

  # ============================================================
  # Backend-agnostic tests (run with whatever backend is available)
  # ============================================================

  describe "backend-agnostic behavior", :toml_parsing do
    describe "#fallthrough_node?" do
      let(:valid_toml) { 'title = "My App"' }

      subject(:analysis) { described_class.new(valid_toml) }

      it "returns true for NodeWrapper instances" do
        node_wrapper = analysis.root_node
        expect(analysis.fallthrough_node?(node_wrapper)).to be true
      end

      it "returns false for other objects" do
        expect(analysis.fallthrough_node?("string")).to be false
        expect(analysis.fallthrough_node?(123)).to be false
      end
    end

    describe "invalid parsing fast paths" do
      it "returns [] for #tables when invalid" do
        analysis = described_class.allocate
        analysis.instance_variable_set(:@errors, ["boom"])
        analysis.instance_variable_set(:@ast, nil)

        expect(analysis.tables).to eq([])
      end

      it "returns [] for #root_pairs when invalid" do
        analysis = described_class.allocate
        analysis.instance_variable_set(:@errors, ["boom"])
        analysis.instance_variable_set(:@ast, nil)

        expect(analysis.root_pairs).to eq([])
      end

      it "skips nil signatures when building signature_map" do
        analysis = described_class.allocate
        analysis.instance_variable_set(:@errors, [])
        analysis.instance_variable_set(:@ast, nil)

        wrapper = instance_double(Toml::Merge::NodeWrapper)
        allow(analysis).to receive(:statements).and_return([wrapper])
        allow(analysis).to receive(:generate_signature).with(wrapper).and_return(nil)

        expect(analysis.signature_map).to eq({})
      end
    end

    describe ".find_parser_path" do
      it "returns a string path or nil" do
        path = described_class.find_parser_path
        expect(path.is_a?(String) || path.nil?).to be true
      end
    end

    describe "error handling" do
      it "handles TreeHaver::NotAvailable gracefully" do
        allow(TreeHaver).to receive(:parser_for).and_raise(TreeHaver::NotAvailable.new("No parser available"))

        analysis = described_class.new("key = \"value\"")
        expect(analysis.valid?).to be false
        expect(analysis.errors).not_to be_empty
        expect(analysis.errors.first).to include("No parser available")
      end

      it "handles other StandardError gracefully" do
        allow(TreeHaver).to receive(:parser_for).and_raise(StandardError.new("Unexpected error"))

        analysis = described_class.new("key = \"value\"")
        expect(analysis.valid?).to be false
        expect(analysis.errors).not_to be_empty
      end
    end

    describe "with parse errors" do
      let(:incomplete_toml) { "key = " }

      it "handles incomplete TOML" do
        analysis = described_class.new(incomplete_toml)
        # May or may not be valid depending on backend's error recovery
        expect(analysis.valid?).to be(true).or be(false)
      end
    end
  end

  # ============================================================
  # Tree-sitter specific tests (features not available in Citrus)
  # ============================================================

  describe "tree-sitter specific behavior", :toml_grammar do
    it "handles invalid parser path gracefully" do
      # Only tree-sitter uses parser_path; Citrus ignores it
      # Need to ensure we're NOT using Citrus for this test
      skip "Only applies when tree-sitter backend is active" if TreeHaver.effective_backend == :citrus

      analysis = described_class.new("key = \"value\"", parser_path: "/nonexistent/path/to/parser.so")
      expect(analysis.valid?).to be false
      expect(analysis.errors).not_to be_empty
    end
  end
end

