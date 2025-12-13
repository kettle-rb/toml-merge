# frozen_string_literal: true

RSpec.describe Toml::Merge::NodeWrapper do
  # We can't easily test NodeWrapper without a real tree-sitter node,
  # so these tests focus on the interface and behavior with mocked nodes.

  let(:mock_node) do
    instance_double(
      TreeSitter::Node,
      type: "pair",
      start_point: double(row: 0, column: 0),
      end_point: double(row: 0, column: 10),
      child_count: 2,
      child: ->(_i) { nil },
      text: 'key = "value"',
    )
  end

  describe ".wrap" do
    it "returns nil for nil input" do
      expect(described_class.wrap(nil, [])).to be_nil
    end

    # Note: Full tests require actual tree-sitter nodes
  end

  describe "signature computation" do
    before do
      skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
    end

    it "generates signatures for table nodes" do
      # A table like [server] should have signature [:table, "server"]
      toml = "[server]\nport = 8080"
      wrapper = parse_toml(toml, node_type: "table")

      expect(wrapper).not_to be_nil
      expect(wrapper.signature).to eq([:table, "server"])
    end

    it "generates signatures for pair nodes" do
      # A pair like port = 8080 should have signature [:pair, "port"]
      toml = "port = 8080"
      wrapper = parse_toml(toml, node_type: "pair")

      expect(wrapper).not_to be_nil
      expect(wrapper.signature).to eq([:pair, "port"])
    end

    it "generates signatures for array of tables" do
      # An array like [[servers]] should have signature [:array_of_tables, "servers"]
      toml = "[[servers]]\nname = \"web\""

      # Try different possible node types for array of tables
      wrapper = parse_toml(toml, node_type: "table_array_element") ||
                parse_toml(toml, node_type: "array_of_tables") ||
                parse_toml(toml, node_type: "table_array")

      expect(wrapper).not_to be_nil, "Could not find array of tables node - check tree-sitter-toml grammar"

      # The signature should identify it as an array of tables with the name
      sig = wrapper.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:array_of_tables).or eq(:table_array_element).or eq(:table_array)
      expect(sig.last).to eq("servers")
    end
  end
end
