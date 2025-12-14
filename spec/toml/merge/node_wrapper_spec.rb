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

  describe "#initialize" do
    it "handles nodes without start_point method" do
      node_without_start = instance_double(TreeSitter::Node, type: "pair")
      allow(node_without_start).to receive(:respond_to?).with(:start_point).and_return(false)
      allow(node_without_start).to receive(:respond_to?).with(:end_point).and_return(true)
      allow(node_without_start).to receive(:end_point).and_return(double(row: 5, column: 10))

      wrapper = described_class.new(node_without_start, lines: ["line1", "line2"])
      expect(wrapper.start_line).to be_nil
      expect(wrapper.end_line).to eq(6) # 5 + 1
    end

    it "handles nodes without end_point method" do
      node_without_end = instance_double(TreeSitter::Node, type: "pair")
      allow(node_without_end).to receive(:respond_to?) do |meth|
        meth == :start_point
      end
      allow(node_without_end).to receive(:start_point).and_return(double(row: 2, column: 5))

      wrapper = described_class.new(node_without_end, lines: ["line1", "line2", "line3"])
      expect(wrapper.start_line).to eq(3) # 2 + 1
      expect(wrapper.end_line).to be_nil
    end

    it "corrects end_line when it is before start_line" do
      node_with_invalid_lines = instance_double(TreeSitter::Node, type: "pair")
      allow(node_with_invalid_lines).to receive(:respond_to?) do |meth|
        %i[start_point end_point].include?(meth)
      end
      allow(node_with_invalid_lines).to receive_messages(
        start_point: double(row: 5, column: 0),
        end_point: double(row: 2, column: 10),
      )

      wrapper = described_class.new(node_with_invalid_lines, lines: ["line1", "line2", "line3", "line4", "line5", "line6"])
      expect(wrapper.start_line).to eq(6) # 5 + 1
      expect(wrapper.end_line).to eq(6) # corrected to match start_line
    end
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

    it "generates signatures for document nodes" do
      toml = "port = 8080"
      wrapper = parse_toml(toml) # root document
      expect(wrapper).not_to be_nil
      expect(wrapper.signature).to eq([:document])
    end

    it "generates signatures for inline table nodes" do
      toml = "config = { a = 1, b = 2 }"
      wrapper = parse_toml(toml, node_type: "inline_table")
      expect(wrapper).not_to be_nil
      sig = wrapper.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:inline_table)
      expect(sig.last).to contain_exactly("a", "b")
    end

    it "generates signatures for array nodes" do
      toml = "items = [1, 2, 3]"
      wrapper = parse_toml(toml, node_type: "array")
      expect(wrapper).not_to be_nil
      sig = wrapper.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:array)
      expect(sig.last).to be_an(Integer)
    end

    it "generates signatures for integer value nodes" do
      toml = "port = 8080"
      wrapper = parse_toml(toml, node_type: "integer")
      expect(wrapper).not_to be_nil
      expect(wrapper.signature).to eq([:integer, "8080"])
    end

    it "generates signatures for float value nodes" do
      toml = "pi = 3.14"
      wrapper = parse_toml(toml, node_type: "float")
      expect(wrapper).not_to be_nil
      expect(wrapper.signature).to eq([:float, "3.14"])
    end

    it "generates signatures for boolean value nodes" do
      toml = "enabled = true"
      wrapper = parse_toml(toml, node_type: "boolean")
      expect(wrapper).not_to be_nil
      expect(wrapper.signature).to eq([:boolean, "true"])
    end

    it "generates signatures for string value nodes" do
      toml = "name = \"test\""
      wrapper = parse_toml(toml, node_type: "string")
      expect(wrapper).not_to be_nil
      sig = wrapper.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:string)
      expect(sig.last).to eq("\"test\"")
    end

    it "generates signatures for datetime value nodes" do
      toml = "date = 2023-01-01"
      wrapper = parse_toml(toml, node_type: "local_date")
      expect(wrapper).not_to be_nil
      sig = wrapper.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:datetime)
    end

    it "generates signatures for comment nodes" do
      toml = "# This is a comment\nport = 8080"
      wrapper = parse_toml(toml, node_type: "comment")
      expect(wrapper).not_to be_nil
      sig = wrapper.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:comment)
      expect(sig.last).to eq("# This is a comment")
    end
  end

  describe "predicate methods" do
    before do
      skip "Requires tree-sitter TOML parser" unless tree_sitter_available?
    end

    it "correctly identifies table nodes" do
      toml = "[server]\nport = 8080"
      table = parse_toml(toml, node_type: "table")
      expect(table).not_to be_nil
      expect(table.table?).to be true
      expect(table.array_of_tables?).to be false
      expect(table.pair?).to be false
      expect(table.container?).to be true
      expect(table.leaf?).to be false
    end

    it "correctly identifies array of tables nodes" do
      toml = "[[servers]]\nname = \"web\""
      aot = parse_toml(toml, node_type: "table_array_element") ||
        parse_toml(toml, node_type: "array_of_tables") ||
        parse_toml(toml, node_type: "table_array")
      expect(aot).not_to be_nil
      expect(aot.table?).to be false
      expect(aot.array_of_tables?).to be true
      expect(aot.pair?).to be false
      expect(aot.container?).to be true
      expect(aot.leaf?).to be false
    end

    it "correctly identifies pair nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.table?).to be false
      expect(pair.array_of_tables?).to be false
      expect(pair.pair?).to be true
      expect(pair.container?).to be false
      expect(pair.leaf?).to be true
    end

    it "correctly identifies integer value nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      expect(value.integer?).to be true
      expect(value.float?).to be false
      expect(value.boolean?).to be false
      expect(value.string?).to be false
      expect(value.array?).to be false
      expect(value.inline_table?).to be false
    end

    it "correctly identifies string value nodes" do
      toml = "name = \"test\""
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      expect(value.integer?).to be false
      expect(value.float?).to be false
      expect(value.boolean?).to be false
      expect(value.string?).to be true
      expect(value.array?).to be false
      expect(value.inline_table?).to be false
    end

    it "correctly identifies boolean value nodes" do
      toml = "enabled = true"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      expect(value.integer?).to be false
      expect(value.float?).to be false
      expect(value.boolean?).to be true
      expect(value.string?).to be false
      expect(value.array?).to be false
      expect(value.inline_table?).to be false
    end

    it "correctly identifies array value nodes" do
      toml = "items = [1, 2, 3]"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      expect(value.array?).to be true
      expect(value.container?).to be true
      expect(value.leaf?).to be false
    end

    it "correctly identifies inline table value nodes" do
      toml = "config = { a = 1, b = 2 }"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      expect(value.integer?).to be false
      expect(value.float?).to be false
      expect(value.boolean?).to be false
      expect(value.string?).to be false
      expect(value.array?).to be false
      expect(value.inline_table?).to be true
      expect(value.container?).to be true
      expect(value.leaf?).to be false
    end

    it "correctly identifies datetime value nodes" do
      toml = "created = 2023-01-01T00:00:00Z"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      expect(value.datetime?).to be true
    end

    it "tests type? method" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.type?("pair")).to be true
      expect(pair.type?("table")).to be false
      expect(pair.type?(:pair)).to be true
      expect(pair.type?(:table)).to be false
    end

    it "returns nil for key_name when called on non-pair nodes" do
      toml = "[server]\nport = 8080"
      table = parse_toml(toml, node_type: "table")
      expect(table).not_to be_nil
      expect(table.key_name).to be_nil
    end

    it "returns nil for table_name when called on non-table nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.table_name).to be_nil
    end

    it "returns nil for value_node when called on non-pair nodes" do
      toml = "[server]\nport = 8080"
      table = parse_toml(toml, node_type: "table")
      expect(table).not_to be_nil
      expect(table.value_node).to be_nil
    end

    it "returns empty array for pairs when called on non-table/inline_table/document nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.pairs).to eq([])
    end

    it "returns empty array for elements when called on non-array nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.elements).to eq([])
    end

    it "returns nil for opening_line when called on non-table/array_of_tables nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.opening_line).to be_nil
    end

    it "returns empty array for mergeable_children on leaf nodes" do
      toml = "port = 8080"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      expect(pair.mergeable_children).to eq([])
    end

    it "returns mergeable children for array nodes" do
      toml = "items = [1, 2, 3]"
      pair = parse_toml(toml, node_type: "pair")
      expect(pair).not_to be_nil
      value = pair.value_node
      children = value.mergeable_children
      expect(children).to be_an(Array)
      expect(children.size).to eq(3) # array elements
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
      expect(table.closing_line.nil? || table.closing_line == "[block]").to be(true)
      # text/content should include the source slice
      expect(table.text).to be_a(String)
      expect(table.content).to include("[block]")
    end
  end
end
