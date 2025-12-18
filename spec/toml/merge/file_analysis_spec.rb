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
      it "raises StandardError" do
        expect {
          described_class.new(invalid_toml)
        }.to raise_error(StandardError, /TOML parse error/)
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
end
