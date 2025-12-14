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

  describe ".find_parser_path" do
    it "returns path from environment variable when set and file exists" do
      stub_env("TREE_SITTER_TOML_PATH" => "/fake/path/libtree-sitter-toml.so")
      allow(File).to receive(:exist?).with("/fake/path/libtree-sitter-toml.so").and_return(true)

      expect(described_class.find_parser_path).to eq("/fake/path/libtree-sitter-toml.so")
    end

    it "searches common paths when env var not set" do
      stub_env("TREE_SITTER_TOML_PATH" => nil)
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with("/usr/lib/libtree-sitter-toml.so").and_return(true)

      expect(described_class.find_parser_path).to eq("/usr/lib/libtree-sitter-toml.so")
    end

    it "returns nil when no parser found" do
      stub_env("TREE_SITTER_TOML_PATH" => nil)
      allow(File).to receive(:exist?).and_return(false)

      expect(described_class.find_parser_path).to be_nil
    end
  end

  describe "#initialize" do
    context "with custom parser_path" do
      it "uses provided parser path" do
        allow(File).to receive(:exist?).with("/custom/path").and_return(true)
        
        # Mock the tree-sitter objects properly
        mock_language = double("TreeSitter::Language")
        mock_parser = double("TreeSitter::Parser")
        mock_root_node = double("TreeSitter::Node", has_error?: false, each: [])
        mock_tree = double("TreeSitter::Tree", root_node: mock_root_node)
        
        allow(TreeSitter::Language).to receive(:load).and_return(mock_language)
        allow(TreeSitter::Parser).to receive(:new).and_return(mock_parser)
        allow(mock_parser).to receive(:language=).with(mock_language)
        allow(mock_parser).to receive(:parse_string).and_return(mock_tree)

        analysis = described_class.new(valid_toml, parser_path: "/custom/path")
        expect(analysis.instance_variable_get(:@parser_path)).to eq("/custom/path")
      end

      context "with custom parser_path that doesn't exist" do
        it "raises StandardError" do
          allow(File).to receive(:exist?).with("/custom/path").and_return(false)
          
          expect {
            described_class.new(valid_toml, parser_path: "/custom/path")
          }.to raise_error(StandardError, /Tree-sitter toml parser not found/)
        end
      end
    end

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
end
