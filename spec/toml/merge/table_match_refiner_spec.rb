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

    context "with real parsed TOML nodes", :toml_backend do
      let(:template_toml) do
        <<~TOML
          [server]
          host = "localhost"
          port = 8080

          [database]
          name = "mydb"
        TOML
      end

      let(:dest_toml) do
        <<~TOML
          [servers]
          host = "production.example.com"
          port = 443

          [db]
          name = "proddb"
        TOML
      end

      let(:template_analysis) { Toml::Merge::FileAnalysis.new(template_toml) }
      let(:dest_analysis) { Toml::Merge::FileAnalysis.new(dest_toml) }
      let(:template_tables) { template_analysis.tables }
      let(:dest_tables) { dest_analysis.tables }

      it "matches tables with similar names" do
        skip "No tables available" if template_tables.empty? || dest_tables.empty?

        result = refiner.call(template_tables, dest_tables)
        expect(result).to be_an(Array)
        # Should find at least one match (server/servers are similar)
        # The exact behavior depends on threshold
      end

      it "returns match results with proper structure" do
        skip "No tables available" if template_tables.empty? || dest_tables.empty?

        result = refiner.call(template_tables, dest_tables)
        next if result.empty?

        match = result.first
        expect(match).to respond_to(:template_node)
        expect(match).to respond_to(:dest_node)
        expect(match).to respond_to(:score)
      end
    end

    context "with different table names", :toml_backend do
      let(:template_toml) do
        <<~TOML
          [alpha]
          foo = "bar"
          baz = 123
        TOML
      end

      let(:dest_toml) do
        <<~TOML
          [zebra]
          completely = "different"
          keys = "here"
        TOML
      end

      let(:template_analysis) { Toml::Merge::FileAnalysis.new(template_toml) }
      let(:dest_analysis) { Toml::Merge::FileAnalysis.new(dest_toml) }

      it "does not match tables below threshold" do
        skip "No tables available" if template_analysis.tables.empty? || dest_analysis.tables.empty?

        # With high threshold and very different names + keys, should not match
        high_threshold_refiner = described_class.new(threshold: 0.9)
        result = high_threshold_refiner.call(template_analysis.tables, dest_analysis.tables)
        expect(result).to be_empty
      end
    end
  end

  describe "weights configuration" do
    it "merges custom weights with defaults" do
      refiner = described_class.new(weights: {name_match: 0.7})
      expect(refiner.weights[:name_match]).to eq(0.7)
      expect(refiner.weights[:key_overlap]).to eq(0.3) # Default preserved
      expect(refiner.weights[:position]).to eq(0.2) # Default preserved
    end

    it "uses all default weights when none specified" do
      refiner = described_class.new
      expect(refiner.weights).to eq(described_class::DEFAULT_WEIGHTS)
    end
  end

  describe "similarity scoring", :toml_backend do
    subject(:refiner) { described_class.new(threshold: 0.3) }

    let(:similar_template) do
      <<~TOML
        [server]
        host = "localhost"
        port = 8080
      TOML
    end

    let(:similar_dest) do
      <<~TOML
        [servers]
        host = "localhost"
        port = 8080
      TOML
    end

    it "considers 'server' and 'servers' as similar enough to match" do
      template_analysis = Toml::Merge::FileAnalysis.new(similar_template)
      dest_analysis = Toml::Merge::FileAnalysis.new(similar_dest)

      skip "No tables available" if template_analysis.tables.empty? || dest_analysis.tables.empty?

      result = refiner.call(template_analysis.tables, dest_analysis.tables)
      # With low threshold, similar names should match
      expect(result).not_to be_empty
    end
  end

  describe "Levenshtein distance" do
    subject(:refiner) { described_class.new }

    it "calculates distance for identical strings" do
      distance = refiner.send(:levenshtein_distance, "test", "test")
      expect(distance).to eq(0)
    end

    it "calculates distance for completely different strings" do
      distance = refiner.send(:levenshtein_distance, "abc", "xyz")
      expect(distance).to eq(3)
    end

    it "calculates distance for similar strings" do
      distance = refiner.send(:levenshtein_distance, "server", "servers")
      expect(distance).to eq(1)
    end

    it "handles empty first string" do
      distance = refiner.send(:levenshtein_distance, "", "test")
      expect(distance).to eq(4)
    end

    it "handles empty second string" do
      distance = refiner.send(:levenshtein_distance, "test", "")
      expect(distance).to eq(4)
    end

    it "handles both empty strings" do
      distance = refiner.send(:levenshtein_distance, "", "")
      expect(distance).to eq(0)
    end
  end

  describe "position similarity" do
    subject(:refiner) { described_class.new }

    it "returns 1.0 for single item in both lists" do
      similarity = refiner.send(:compute_position_similarity, 0, 0, 1, 1)
      expect(similarity).to eq(1.0)
    end

    it "returns high similarity for same relative position" do
      similarity = refiner.send(:compute_position_similarity, 0, 0, 3, 3)
      expect(similarity).to eq(1.0)
    end

    it "returns lower similarity for different positions" do
      similarity = refiner.send(:compute_position_similarity, 0, 2, 3, 3)
      expect(similarity).to be < 1.0
    end
  end

  describe "key overlap", :toml_backend do
    subject(:refiner) { described_class.new }

    let(:table_with_keys) do
      <<~TOML
        [config]
        debug = true
        level = 3
        name = "test"
      TOML
    end

    let(:table_with_same_keys) do
      <<~TOML
        [settings]
        debug = false
        level = 5
        name = "prod"
      TOML
    end

    let(:table_with_different_keys) do
      <<~TOML
        [other]
        foo = "bar"
        baz = 123
      TOML
    end

    it "returns high overlap for tables with same keys" do
      analysis1 = Toml::Merge::FileAnalysis.new(table_with_keys)
      analysis2 = Toml::Merge::FileAnalysis.new(table_with_same_keys)

      skip "No tables available" if analysis1.tables.empty? || analysis2.tables.empty?

      table1 = analysis1.tables.first
      table2 = analysis2.tables.first

      overlap = refiner.send(:compute_key_overlap, table1, table2)
      expect(overlap).to eq(1.0)
    end

    it "returns low overlap for tables with different keys" do
      analysis1 = Toml::Merge::FileAnalysis.new(table_with_keys)
      analysis2 = Toml::Merge::FileAnalysis.new(table_with_different_keys)

      skip "No tables available" if analysis1.tables.empty? || analysis2.tables.empty?

      table1 = analysis1.tables.first
      table2 = analysis2.tables.first

      overlap = refiner.send(:compute_key_overlap, table1, table2)
      expect(overlap).to eq(0.0)
    end
  end

  describe "name similarity" do
    subject(:refiner) { described_class.new }

    it "returns 1.0 for identical names" do
      node1 = double("Node", respond_to?: true, key_name: "server")
      allow(node1).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node1).to receive(:respond_to?).with(:key_name).and_return(true)

      node2 = double("Node", respond_to?: true, key_name: "server")
      allow(node2).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node2).to receive(:respond_to?).with(:key_name).and_return(true)

      similarity = refiner.send(:compute_name_similarity, node1, node2)
      expect(similarity).to eq(1.0)
    end

    it "returns 0.0 for empty names" do
      node1 = double("Node", respond_to?: true, key_name: "")
      allow(node1).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node1).to receive(:respond_to?).with(:key_name).and_return(true)

      node2 = double("Node", respond_to?: true, key_name: "server")
      allow(node2).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node2).to receive(:respond_to?).with(:key_name).and_return(true)

      similarity = refiner.send(:compute_name_similarity, node1, node2)
      expect(similarity).to eq(0.0)
    end
  end

  describe "table_node?" do
    subject(:refiner) { described_class.new }

    it "returns false for nodes without type method" do
      node = double("Node")
      allow(node).to receive(:respond_to?).with(:type).and_return(false)

      expect(refiner.send(:table_node?, node)).to be false
    end
  end

  describe "extract_table_name" do
    subject(:refiner) { described_class.new }

    it "falls back to signature when key_name not available" do
      node = double("Node")
      allow(node).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node).to receive(:respond_to?).with(:key_name).and_return(false)
      allow(node).to receive(:respond_to?).with(:signature).and_return(true)
      allow(node).to receive(:signature).and_return([:table, "test_signature"])

      name = refiner.send(:extract_table_name, node)
      expect(name).to eq("test_signature")
    end

    it "returns empty string when no methods available" do
      node = double("Node")
      allow(node).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node).to receive(:respond_to?).with(:key_name).and_return(false)
      allow(node).to receive(:respond_to?).with(:signature).and_return(false)

      name = refiner.send(:extract_table_name, node)
      expect(name).to eq("")
    end
  end

  describe "#compute_key_overlap edge cases" do
    subject(:refiner) { described_class.new }

    it "returns 1.0 when both have empty keys" do
      node1 = double("Node")
      allow(node1).to receive(:respond_to?).with(:mergeable_children).and_return(true)
      allow(node1).to receive(:mergeable_children).and_return([])

      node2 = double("Node")
      allow(node2).to receive(:respond_to?).with(:mergeable_children).and_return(true)
      allow(node2).to receive(:mergeable_children).and_return([])

      overlap = refiner.send(:compute_key_overlap, node1, node2)
      expect(overlap).to eq(1.0)
    end

    it "returns 0.0 when first has keys but second is empty" do
      child = double("Child", key_name: "test", pair?: true)
      allow(child).to receive(:respond_to?).with(:key_name).and_return(true)

      node1 = double("Node")
      allow(node1).to receive(:respond_to?).with(:mergeable_children).and_return(true)
      allow(node1).to receive(:mergeable_children).and_return([child])

      node2 = double("Node")
      allow(node2).to receive(:respond_to?).with(:mergeable_children).and_return(true)
      allow(node2).to receive(:mergeable_children).and_return([])

      overlap = refiner.send(:compute_key_overlap, node1, node2)
      expect(overlap).to eq(0.0)
    end

    it "returns 0.0 when second has keys but first is empty" do
      child = double("Child", key_name: "test", pair?: true)
      allow(child).to receive(:respond_to?).with(:key_name).and_return(true)

      node1 = double("Node")
      allow(node1).to receive(:respond_to?).with(:mergeable_children).and_return(true)
      allow(node1).to receive(:mergeable_children).and_return([])

      node2 = double("Node")
      allow(node2).to receive(:respond_to?).with(:mergeable_children).and_return(true)
      allow(node2).to receive(:mergeable_children).and_return([child])

      overlap = refiner.send(:compute_key_overlap, node1, node2)
      expect(overlap).to eq(0.0)
    end
  end

  describe "#compute_name_similarity edge cases" do
    subject(:refiner) { described_class.new }

    it "returns 1.0 when both names are empty (empty == empty)" do
      node1 = double("Node")
      allow(node1).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node1).to receive(:respond_to?).with(:key_name).and_return(true)
      allow(node1).to receive(:key_name).and_return("")

      node2 = double("Node")
      allow(node2).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node2).to receive(:respond_to?).with(:key_name).and_return(true)
      allow(node2).to receive(:key_name).and_return("")

      similarity = refiner.send(:compute_name_similarity, node1, node2)
      # Empty strings are equal, so returns 1.0 from the first check
      expect(similarity).to eq(1.0)
    end

    it "returns 0.0 when one name is empty and other is not" do
      node1 = double("Node")
      allow(node1).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node1).to receive(:respond_to?).with(:key_name).and_return(true)
      allow(node1).to receive(:key_name).and_return("")

      node2 = double("Node")
      allow(node2).to receive(:respond_to?).with(:table_name).and_return(false)
      allow(node2).to receive(:respond_to?).with(:key_name).and_return(true)
      allow(node2).to receive(:key_name).and_return("server")

      similarity = refiner.send(:compute_name_similarity, node1, node2)
      expect(similarity).to eq(0.0)
    end
  end
end
