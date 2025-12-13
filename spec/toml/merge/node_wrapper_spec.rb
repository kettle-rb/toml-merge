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

  describe "predicates and accessors with real parser" do
    before do
      skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
    end

    it "extracts table_name and pairs from a table" do
      toml = <<~TOML
        # config
        [server]
        host = "localhost"
        port = 8080
      TOML
      table = parse_toml(toml, node_type: "table")
      expect(table).not_to be_nil
      expect(table.table?).to be true
      expect(table.table_name).to eq("server")

      # pairs from table
      ps = table.pairs
      expect(ps.map(&:pair?)).to all(be true)
      keys = ps.map(&:key_name)
      expect(keys).to contain_exactly("host", "port")

      # value_node for a pair
      host_pair = ps.find { |p| p.key_name == "host" }
      expect(host_pair.value_node.string?).to be true
    end

    it "detects array_of_tables and exposes mergeable_children" do
      toml = <<~TOML
        [[servers]]
        name = "web"
        [[servers]]
        name = "db"
      TOML
      aot = parse_toml(toml, node_type: "table_array_element") ||
        parse_toml(toml, node_type: "array_of_tables") ||
        parse_toml(toml, node_type: "table_array")
      expect(aot).not_to be_nil
      expect(aot.array_of_tables?).to be true
      expect(aot.container?).to be true
      expect(aot.leaf?).to be false
      # mergeable_children returns child nodes to consider during merge
      children = aot.mergeable_children
      expect(children).to be_a(Array)
      expect(children).to all(be_a(described_class))
    end

    it "handles inline_table keys and pairs" do
      toml = "config = { a = 1, b = 2 }"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.pair?).to be true
      expect(pair.key_name).to eq("config")

      value = pair.value_node
      expect(value.inline_table?).to be true
      ps = value.pairs
      expect(ps.map(&:key_name)).to contain_exactly("a", "b")
    end

    it "exposes opening_line/closing_line/text/content ranges" do
      toml = <<~TOML
        [block]
        a = 1
        b = 2
      TOML
      table = parse_toml(toml, node_type: "table")
      expect(table.opening_line).to eq("[block]")
      # For table headers, closing_line may be the header line or nil (parser dependent)
      expect([nil, "[block]"]).to include(table.closing_line)
      # text/content should include the source slice
      expect(table.text).to be_a(String)
      expect(table.content).to include("[block]")
    end
  end
end
