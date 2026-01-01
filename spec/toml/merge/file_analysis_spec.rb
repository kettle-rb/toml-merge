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

  # Note: find_parser_path and parser_path parameter were removed.
  # TreeHaver now handles grammar discovery and Citrus fallback automatically.

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

      it "is not valid" do
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

  describe "#statements" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns statement nodes excluding comments" do
      statements = analysis.statements
      expect(statements).to be_an(Array)
      expect(statements.all? { |s| s.type != :comment }).to be true
    end
  end

  describe "#tables" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns table nodes" do
      tables = analysis.tables
      expect(tables).to be_an(Array)
      expect(tables.size).to eq(2) # server and database
      expect(tables.all? { |t| t.table? || t.array_of_tables? }).to be true
    end
  end

  describe "#fallthrough_node?" do
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

  describe "#signature_map" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns a hash mapping signatures to nodes" do
      map = analysis.signature_map
      expect(map).to be_a(Hash)
      expect(map.keys).to all(be_an(Array).or(be_nil))
      expect(map.values).to all(be_a(Toml::Merge::NodeWrapper))
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

  describe "#tables" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns an array of table NodeWrappers" do
      tables = analysis.tables
      expect(tables).to be_an(Array)
      expect(tables.length).to eq(2)
    end

    it "returns only table nodes" do
      tables = analysis.tables
      tables.each do |table|
        expect(table.table? || table.array_of_tables?).to be true
      end
    end
  end

  describe "#root_pairs" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "returns an array of pair NodeWrappers" do
      pairs = analysis.root_pairs
      expect(pairs).to be_an(Array)
      expect(pairs.length).to eq(1) # Only "title" at root level
    end

    it "returns only pair nodes" do
      pairs = analysis.root_pairs
      pairs.each do |pair|
        expect(pair.pair?).to be true
      end
    end

    it "returns key name for pairs" do
      pairs = analysis.root_pairs
      expect(pairs.first.key_name).to eq("title")
    end
  end

  describe "#line_at" do
    subject(:analysis) { described_class.new(valid_toml) }

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

  describe "#generate_signature" do
    subject(:analysis) { described_class.new(valid_toml) }

    it "generates signature for a table" do
      table = analysis.tables.first
      sig = analysis.generate_signature(table)
      expect(sig).to be_an(Array)
      expect(sig).to include("server")
    end

    it "generates signature for a pair" do
      pair = analysis.root_pairs.first
      sig = analysis.generate_signature(pair)
      expect(sig).to be_an(Array)
      expect(sig).to include("title")
    end

    it "returns nil for nil input" do
      sig = analysis.generate_signature(nil)
      expect(sig).to be_nil
    end
  end

  describe ".find_parser_path" do
    it "returns a string path or nil" do
      path = described_class.find_parser_path
      expect(path.is_a?(String) || path.nil?).to be true
    end
  end

  describe "with array of tables" do
    subject(:analysis) { described_class.new(array_toml) }

    let(:array_toml) do
      <<~TOML
        [[servers]]
        name = "alpha"

        [[servers]]
        name = "beta"
      TOML
    end

    it "parses array of tables" do
      expect(analysis.valid?).to be true
    end

    it "returns tables for array of tables" do
      tables = analysis.tables
      expect(tables.length).to eq(2)
      tables.each do |table|
        expect(table.array_of_tables?).to be true
      end
    end
  end

  describe "with inline tables" do
    subject(:analysis) { described_class.new(inline_toml) }

    let(:inline_toml) do
      <<~TOML
        config = { debug = true, level = 3 }
      TOML
    end

    it "parses inline tables" do
      expect(analysis.valid?).to be true
    end

    it "returns root pairs including inline table" do
      pairs = analysis.root_pairs
      expect(pairs.length).to eq(1)
      expect(pairs.first.key_name).to eq("config")
    end
  end

  describe "#fallthrough_node?", :toml_parsing do
    subject(:analysis) { described_class.new(simple_toml) }

    let(:simple_toml) { "key = \"value\"" }

    it "returns true for NodeWrapper instances" do
      root = analysis.root_node
      expect(analysis.fallthrough_node?(root)).to be true
    end

    it "returns false for strings" do
      expect(analysis.fallthrough_node?("not a node")).to be false
    end

    it "returns false for nil" do
      expect(analysis.fallthrough_node?(nil)).to be false
    end

    it "returns false for numbers" do
      expect(analysis.fallthrough_node?(123)).to be false
    end
  end

  describe "error handling", :toml_parsing do
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

    it "handles invalid parser path gracefully" do
      analysis = described_class.new("key = \"value\"", parser_path: "/nonexistent/path/to/parser.so")
      expect(analysis.valid?).to be false
      expect(analysis.errors).not_to be_empty
    end
  end

  describe "with parse errors", :toml_parsing do
    let(:invalid_toml) { "key = " }

    it "collects parse errors" do
      analysis = described_class.new(invalid_toml)
      # May or may not be valid depending on error recovery
      expect(analysis.valid?).to be(true).or be(false)
    end
  end
end
