# frozen_string_literal: true

RSpec.describe Toml::Merge::TableMatchRefiner do
  describe "#initialize" do
    it "accepts a threshold" do
      refiner = described_class.new(threshold: 0.6)
      expect(refiner.threshold).to eq(0.6)
    end

    it "accepts custom weights" do
      refiner = described_class.new(weights: {name_match: 0.7})
      expect(refiner.weights[:name_match]).to eq(0.7)
    end

    it "uses default threshold when not specified" do
      refiner = described_class.new
      expect(refiner.threshold).to eq(Ast::Merge::MatchRefinerBase::DEFAULT_THRESHOLD)
    end
  end

  describe "#extract_table_name" do
    subject(:refiner) { described_class.new }

    before do
      skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
    end

    it "extracts name from table node" do
      toml = "[server]\nport = 8080"
      node = parse_toml(toml, node_type: "table")
      expect(refiner.send(:extract_table_name, node)).to eq("server")
    end

    it "extracts name from pair node" do
      toml = "port = 8080"
      node = parse_toml(toml, node_type: "pair")
      expect(refiner.send(:extract_table_name, node)).to eq("port")
    end

    it "extracts name from signature when table_name/key_name not available" do
      # Mock a node without table_name/key_name but with signature
      mock_node = double
      allow(mock_node).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:key_name).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:signature).and_return(true)
      allow(mock_node).to receive(:signature).and_return([:table, "mock_table"])

      expect(refiner.send(:extract_table_name, mock_node)).to eq("mock_table")
    end

    it "returns empty string for nodes without name or signature" do
      mock_node = double
      allow(mock_node).to receive(:respond_to?).and_return(false)

      expect(refiner.send(:extract_table_name, mock_node)).to eq("")
    end
  end

  describe "#compute_position_similarity" do
    subject(:refiner) { described_class.new }

    it "returns 1.0 when both lists have one item" do
      expect(refiner.send(:compute_position_similarity, 0, 0, 1, 1)).to eq(1.0)
    end

    it "computes similarity for multiple items" do
      # Test various positions
      expect(refiner.send(:compute_position_similarity, 0, 0, 3, 3)).to eq(1.0) # same position
      expect(refiner.send(:compute_position_similarity, 0, 2, 3, 3)).to eq(0.0) # opposite positions
      expect(refiner.send(:compute_position_similarity, 1, 1, 3, 3)).to eq(1.0) # middle positions
    end

    it "handles different list sizes" do
      expect(refiner.send(:compute_position_similarity, 0, 0, 2, 3)).to be_between(0, 1)
      expect(refiner.send(:compute_position_similarity, 1, 2, 2, 4)).to be_between(0, 1)
    end
  end

  describe "#call" do
    subject(:refiner) { described_class.new(threshold: 0.5) }

    it "returns an array" do
      result = refiner.call([], [])
      expect(result).to be_an(Array)
    end

    it "returns empty array when no tables provided" do
      result = refiner.call([], [])
      expect(result).to be_empty
    end

    # Full matching tests require actual NodeWrapper objects
    # These document the expected behavior

    context "with similar table names" do
      before do
        skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
      end

      it "matches tables with similar names" do
        template_toml = "[server]\nport = 8080"
        dest_toml = "[servers]\nport = 9090"

        template_node = parse_toml(template_toml, node_type: "table")
        dest_node = parse_toml(dest_toml, node_type: "table")

        expect(template_node).not_to be_nil
        expect(dest_node).not_to be_nil

        matches = refiner.call([template_node], [dest_node])
        expect(matches).not_to be_empty
        expect(matches.first.template_node).to eq(template_node)
        expect(matches.first.dest_node).to eq(dest_node)
      end
    end

    context "with different table names" do
      before do
        skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
      end

      it "does not match tables below threshold" do
        # Use very different table names to ensure they don't match
        # "database" and "application" share some positional similarity,
        # so we use completely different names
        template_toml = "[xyz]\nhost = 'localhost'"
        dest_toml = "[abc]\ntimeout = 30"

        template_node = parse_toml(template_toml, node_type: "table")
        dest_node = parse_toml(dest_toml, node_type: "table")

        expect(template_node).not_to be_nil
        expect(dest_node).not_to be_nil

        matches = refiner.call([template_node], [dest_node])
        expect(matches).to be_empty, "Expected 'xyz' and 'abc' to not match (too dissimilar)"
      end
    end
  end

  describe "Levenshtein distance" do
    subject(:refiner) { described_class.new }

    before do
      skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
    end

    # We test the private method indirectly through similarity scoring
    it "considers 'server' and 'servers' as similar" do
      # This tests that 'server' and 'servers' are similar enough to match
      template_toml = "[server]\nport = 8080"
      dest_toml = "[servers]\nport = 9090"

      template_node = parse_toml(template_toml, node_type: "table")
      dest_node = parse_toml(dest_toml, node_type: "table")

      expect(template_node).not_to be_nil
      expect(dest_node).not_to be_nil

      matches = refiner.call([template_node], [dest_node])
      expect(matches).not_to be_empty, "Expected 'server' and 'servers' to match via Levenshtein distance"
    end
  end
end
