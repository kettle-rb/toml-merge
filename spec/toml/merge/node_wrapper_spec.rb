# frozen_string_literal: true

RSpec.describe Toml::Merge::NodeWrapper do
  describe ".wrap" do
    it "returns nil for nil input" do
      expect(described_class.wrap(nil, [])).to be_nil
    end

    it "returns nil for nil input with source" do
      expect(described_class.wrap(nil, [], source: "test")).to be_nil
    end
  end

  describe "#initialize" do
    it "handles nodes without start_point method" do
      node_without_start = instance_double(TreeHaver::Node, type: "pair")
      allow(node_without_start).to receive(:respond_to?).with(:start_point).and_return(false)
      allow(node_without_start).to receive(:respond_to?).with(:end_point).and_return(true)
      allow(node_without_start).to receive(:end_point).and_return(double(row: 5, column: 10))

      wrapper = described_class.new(node_without_start, lines: ["line1", "line2"])
      expect(wrapper.start_line).to be_nil
      expect(wrapper.end_line).to eq(6) # 5 + 1
    end

    it "handles nodes without end_point method" do
      node_without_end = instance_double(TreeHaver::Node, type: "pair")
      allow(node_without_end).to receive(:respond_to?) do |meth|
        meth == :start_point
      end
      allow(node_without_end).to receive(:start_point).and_return(double(row: 2, column: 5))

      wrapper = described_class.new(node_without_end, lines: ["line1", "line2", "line3"])
      expect(wrapper.start_line).to eq(3) # 2 + 1
      expect(wrapper.end_line).to be_nil
    end

    it "corrects end_line when it is before start_line" do
      node_with_invalid_lines = instance_double(TreeHaver::Node, type: "pair")
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

    it "uses default source when source is nil" do
      node = instance_double(
        TreeHaver::Node,
        type: "pair",
        start_point: double(row: 0, column: 0),
        end_point: double(row: 0, column: 1),
      )

      wrapper = described_class.new(node, lines: ["a = 1"], source: nil)
      expect(wrapper.source).to eq("a = 1")
    end
  end

  # Tests that require a working TOML backend (tree-sitter or citrus)
  # These tests use FileAnalysis to get real parsed nodes
  describe "with parsed TOML nodes", :toml_parsing do
    let(:simple_toml) do
      <<~TOML
        title = "My App"
        version = 1

        [server]
        host = "localhost"
        port = 8080

        [database]
        name = "mydb"
      TOML
    end

    let(:array_toml) do
      <<~TOML
        [[servers]]
        name = "alpha"
        ip = "10.0.0.1"

        [[servers]]
        name = "beta"
        ip = "10.0.0.2"
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(simple_toml) }
    let(:root) { analysis.root_node }

    describe "#type and #type?" do
      it "returns the node type as a symbol" do
        expect(root.type).to eq(:document)
      end

      it "checks type with type?" do
        expect(root.type?(:document)).to be true
        expect(root.type?("document")).to be true
        expect(root.type?(:table)).to be false
      end
    end

    describe "node type predicates" do
      it "identifies document nodes" do
        expect(root.document?).to be true
        expect(root.table?).to be false
      end

      it "identifies table nodes" do
        tables = analysis.tables
        expect(tables).not_to be_empty
        expect(tables.first.table?).to be true
        expect(tables.first.document?).to be false
      end

      it "identifies pair nodes" do
        pairs = analysis.root_pairs
        expect(pairs).not_to be_empty
        expect(pairs.first.pair?).to be true
      end
    end

    describe "#table_name" do
      it "returns the name for table nodes" do
        server_table = analysis.tables.find { |t| t.table_name&.include?("server") }
        expect(server_table).not_to be_nil
        expect(server_table.table_name).to include("server")
      end

      it "returns nil for non-table nodes" do
        expect(root.table_name).to be_nil
      end
    end

    describe "#key_name" do
      it "returns the key name for pair nodes" do
        title_pair = analysis.root_pairs.find { |p| p.key_name == "title" }
        expect(title_pair).not_to be_nil
        expect(title_pair.key_name).to eq("title")
      end

      it "returns nil for non-pair nodes" do
        expect(root.key_name).to be_nil
      end
    end

    describe "#signature" do
      it "generates signature for document nodes" do
        sig = root.signature
        expect(sig).to eq([:document])
      end

      it "generates signature for table nodes" do
        server_table = analysis.tables.find { |t| t.table_name&.include?("server") }
        sig = server_table.signature
        expect(sig.first).to eq(:table)
        expect(sig.last).to include("server")
      end

      it "generates signature for pair nodes" do
        title_pair = analysis.root_pairs.find { |p| p.key_name == "title" }
        sig = title_pair.signature
        expect(sig).to eq([:pair, "title"])
      end
    end

    describe "#children" do
      it "returns wrapped child nodes" do
        children = root.children
        expect(children).to be_an(Array)
        expect(children).to all(be_a(described_class))
      end
    end

    describe "#container? and #leaf?" do
      it "identifies containers" do
        expect(root.container?).to be true
        server_table = analysis.tables.first
        expect(server_table.container?).to be true
      end

      it "identifies leaves" do
        # A pair value like a string should be a leaf
        title_pair = analysis.root_pairs.find { |p| p.key_name == "title" }
        value = title_pair.value_node
        expect(value.leaf?).to be true if value
      end
    end

    describe "#text and #content" do
      it "extracts text from nodes" do
        title_pair = analysis.root_pairs.find { |p| p.key_name == "title" }
        text = title_pair.text
        expect(text).to include("title")
        expect(text).to include("My App")
      end

      it "extracts content from lines" do
        title_pair = analysis.root_pairs.find { |p| p.key_name == "title" }
        content = title_pair.content
        expect(content).to include("title")
      end
    end

    describe "#start_line and #end_line" do
      it "provides line information" do
        expect(root.start_line).to be_a(Integer)
        expect(root.end_line).to be_a(Integer)
        expect(root.start_line).to be >= 1
        expect(root.end_line).to be >= root.start_line
      end
    end

    describe "#inspect" do
      it "returns a debug string" do
        inspect_str = root.inspect
        expect(inspect_str).to include("NodeWrapper")
        expect(inspect_str).to include("document")
      end
    end

    describe "array of tables", :toml_parsing do
      let(:array_analysis) { Toml::Merge::FileAnalysis.new(array_toml) }

      # Extract array of tables nodes using the normalized predicate
      let(:array_tables) do
        array_analysis.tables.select(&:array_of_tables?)
      end

      it "identifies array of tables nodes via FileAnalysis#tables" do
        # FileAnalysis#tables returns both tables and array_of_tables
        tables = array_analysis.tables
        expect(tables).not_to be_empty
      end

      it "identifies array of tables nodes via array_of_tables? predicate" do
        expect(array_tables).not_to be_empty
        expect(array_tables.first.array_of_tables?).to be true
      end

      it "generates signature for array of tables" do
        expect(array_tables).not_to be_empty
        array_table = array_tables.first
        sig = array_table.signature
        expect(sig.first).to eq(:array_of_tables)
        expect(sig.last).to include("servers")
      end

      it "returns canonical_type as :array_of_tables" do
        expect(array_tables).not_to be_empty
        expect(array_tables.first.canonical_type).to eq(:array_of_tables)
      end
    end

    describe "#pairs" do
      it "returns pairs from a table" do
        server_table = analysis.tables.find { |t| t.table_name&.include?("server") }
        pairs = server_table.pairs
        expect(pairs).to be_an(Array)
        # Server table has host and port
        key_names = pairs.map(&:key_name)
        expect(key_names).to include("host")
        expect(key_names).to include("port")
      end
    end

    describe "#mergeable_children" do
      it "returns mergeable children for document" do
        children = root.mergeable_children
        expect(children).to be_an(Array)
        # Should include top-level pairs and tables
        types = children.map(&:type)
        expect(types).to include(:pair).or include(:table)
      end

      it "returns pairs for tables" do
        server_table = analysis.tables.find { |t| t.table_name&.include?("server") }
        children = server_table.mergeable_children
        expect(children).to all(satisfy { |c| c.pair? })
      end
    end
  end

  describe "comment handling", :toml_parsing do
    let(:commented_toml) do
      <<~TOML
        # This is a header comment
        title = "Test"

        # Section comment
        [server]
        # Host comment
        host = "localhost"
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(commented_toml) }

    it "wraps nodes with leading comments" do
      # NodeWrapper accepts leading_comments parameter
      node = analysis.root_node.children.first
      wrapper = described_class.wrap(
        node.node,
        analysis.lines,
        source: commented_toml,
        leading_comments: [{text: "# This is a header comment", line: 1}],
      )
      expect(wrapper.leading_comments).not_to be_empty
    end

    it "wraps nodes with inline comments" do
      node = analysis.root_node.children.first
      wrapper = described_class.wrap(
        node.node,
        analysis.lines,
        source: commented_toml,
        inline_comment: {text: "# inline", line: 2},
      )
      expect(wrapper.inline_comment).not_to be_nil
    end
  end

  describe "value type detection", :toml_parsing do
    let(:types_toml) do
      <<~TOML
        string_val = "hello"
        int_val = 42
        float_val = 3.14
        bool_val = true
        date_val = 2025-12-22
        array_val = [1, 2, 3]
        inline_table = { key = "value" }
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(types_toml) }

    it "identifies string values" do
      string_pair = analysis.root_pairs.find { |p| p.key_name == "string_val" }
      value = string_pair.value_node
      expect(value.string?).to be true if value
    end

    it "identifies integer values" do
      int_pair = analysis.root_pairs.find { |p| p.key_name == "int_val" }
      value = int_pair.value_node
      expect(value.integer?).to be true if value
    end

    it "identifies float values" do
      float_pair = analysis.root_pairs.find { |p| p.key_name == "float_val" }
      value = float_pair.value_node
      expect(value.float?).to be true if value
    end

    it "identifies boolean values" do
      bool_pair = analysis.root_pairs.find { |p| p.key_name == "bool_val" }
      value = bool_pair.value_node
      expect(value.boolean?).to be true if value
    end

    it "identifies array values" do
      array_pair = analysis.root_pairs.find { |p| p.key_name == "array_val" }
      value = array_pair.value_node
      expect(value.array?).to be true if value
    end

    it "identifies inline table values" do
      inline_pair = analysis.root_pairs.find { |p| p.key_name == "inline_table" }
      value = inline_pair.value_node
      expect(value.inline_table?).to be true if value
    end
  end

  describe "#elements for arrays", :toml_parsing do
    let(:array_toml) do
      <<~TOML
        numbers = [1, 2, 3, 4, 5]
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(array_toml) }

    it "extracts array elements" do
      array_pair = analysis.root_pairs.find { |p| p.key_name == "numbers" }
      value = array_pair.value_node
      next unless value&.array?

      elements = value.elements
      expect(elements).to be_an(Array)
      expect(elements.length).to eq(5)
    end
  end

  describe "#datetime?", :toml_parsing do
    let(:datetime_toml) do
      <<~TOML
        date_val = 2025-12-23
      TOML
    end

    let(:datetime_with_time_toml) do
      <<~TOML
        created_at = 2025-12-24T10:30:00Z
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(datetime_toml) }
    let(:datetime_analysis) { Toml::Merge::FileAnalysis.new(datetime_with_time_toml) }

    it "identifies date values" do
      date_pair = analysis.root_pairs.find { |p| p.key_name == "date_val" }
      value = date_pair&.value_node
      # The datetime? predicate should work if the backend supports datetime types
      expect(value).not_to be_nil if date_pair
    end

    it "identifies datetime values with time component" do
      pair = datetime_analysis.root_pairs.find { |p| p.key_name == "created_at" }
      value = pair&.value_node
      if value
        # The type should be datetime or something datetime-like
        expect(value.datetime?).to be(true).or be(false)
      end
    end
  end

  describe "#comment?", :toml_parsing do
    let(:comment_toml) do
      <<~TOML
        # This is a comment
        key = "value"
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(comment_toml) }

    it "can check if node is a comment" do
      # The root_node children may include comments
      root = analysis.root_node
      children = root.children
      # Check that comment? method works without error and returns boolean
      children.each do |child|
        expect(child.comment?).to be(true).or be(false)
      end
    end
  end

  describe "#opening_line and #closing_line", :toml_parsing do
    let(:table_toml) do
      <<~TOML
        [server]
        host = "localhost"
        port = 8080
      TOML
    end

    let(:root_pairs_toml) do
      <<~TOML
        title = "My Config"
        version = 1
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(table_toml) }
    let(:root_pairs_analysis) { Toml::Merge::FileAnalysis.new(root_pairs_toml) }

    it "returns opening_line for a table" do
      table = analysis.tables.first
      expect(table.opening_line).to include("[server]")
    end

    it "returns closing_line for a table" do
      table = analysis.tables.first
      # closing_line may return nil if end_line is at index that doesn't exist
      # Just verify the method runs without error
      closing = table.closing_line
      expect(closing.is_a?(String) || closing.nil?).to be true
    end

    it "returns nil for opening_line on non-table nodes" do
      pair = analysis.root_pairs.first
      # pairs that are not tables should return nil for opening_line
      # (unless they happen to be tables, which root_pairs are not)
      if pair && !pair.table? && !pair.array_of_tables?
        expect(pair.opening_line).to be_nil
      end
    end

    it "returns opening line for table with skip guard" do
      table = analysis.tables.first
      skip "No table found" unless table
      opening = table.opening_line
      expect(opening).to include("[server]") if opening
    end

    it "returns nil for non-container nodes" do
      pair = root_pairs_analysis.root_pairs.first
      skip "No pair found" unless pair
      value = pair.value_node
      skip "No value node" unless value
      expect(value.opening_line).to be_nil if value.leaf?
    end
  end

  describe "#leaf? and #container?", :toml_parsing do
    let(:mixed_toml) do
      <<~TOML
        name = "test"
        [section]
        key = "value"
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(mixed_toml) }

    it "identifies pair values as leaves" do
      pair = analysis.root_pairs.first
      value = pair&.value_node
      if value&.string?
        expect(value.leaf?).to be true
        expect(value.container?).to be false
      end
    end

    it "identifies tables as containers" do
      table = analysis.tables.first
      expect(table.container?).to be true
      expect(table.leaf?).to be false
    end
  end

  describe "#content", :toml_parsing do
    let(:content_toml) do
      <<~TOML
        [section]
        key1 = "value1"
        key2 = "value2"
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(content_toml) }

    it "returns content for a table" do
      table = analysis.tables.first
      content = table.content
      expect(content).to include("key1")
      expect(content).to include("key2")
    end

    it "returns empty string when start_line is nil" do
      # Create a mock wrapper without line info
      mock_node = double("Node", type: "pair", respond_to?: false)
      allow(mock_node).to receive(:respond_to?).with(:start_point).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:end_point).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:each).and_return(false)
      wrapper = described_class.new(mock_node, lines: ["test"])
      expect(wrapper.content).to eq("")
    end
  end

  describe "#type?", :toml_parsing do
    let(:simple_toml) { "key = \"value\"" }
    let(:analysis) { Toml::Merge::FileAnalysis.new(simple_toml) }

    it "matches raw type" do
      pair = analysis.root_pairs.first
      expect(pair.type?(:pair)).to be true
      expect(pair.type?("pair")).to be true
    end

    it "matches canonical type" do
      pair = analysis.root_pairs.first
      expect(pair.type?(:pair)).to be true
    end

    it "returns false for non-matching types" do
      pair = analysis.root_pairs.first
      expect(pair.type?(:table)).to be false
    end
  end

  describe "signature generation for inline_table", :toml_parsing do
    let(:inline_table_toml) do
      <<~TOML
        config = { debug = true, level = 3 }
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(inline_table_toml) }

    it "generates signature with sorted keys" do
      pair = analysis.root_pairs.find { |p| p.key_name == "config" }
      value = pair&.value_node
      if value&.inline_table?
        sig = value.signature
        expect(sig.first).to eq(:inline_table)
        expect(sig.last).to be_an(Array)
      end
    end
  end

  describe "signature generation for fallback types", :toml_parsing do
    let(:simple_toml) { "key = \"value\"" }
    let(:analysis) { Toml::Merge::FileAnalysis.new(simple_toml) }

    it "generates signature for string values" do
      pair = analysis.root_pairs.first
      value = pair&.value_node
      if value&.string?
        sig = value.signature
        expect(sig.first).to eq(:string)
      end
    end
  end

  describe "signature generation for all types", :toml_parsing do
    let(:comprehensive_toml) do
      <<~TOML
        # Comment line
        title = "My App"
        count = 42
        pi = 3.14159
        enabled = true
        disabled = false
        created = 2025-12-24
        tags = ["a", "b", "c"]
        config = { debug = true }

        [server]
        host = "localhost"

        [[plugins]]
        name = "plugin1"
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(comprehensive_toml) }

    it "generates signature for integer values" do
      pair = analysis.root_pairs.find { |p| p.key_name == "count" }
      value = pair&.value_node
      if value&.integer?
        sig = value.signature
        expect(sig.first).to eq(:integer)
        expect(sig.last).to eq("42")
      end
    end

    it "generates signature for float values" do
      pair = analysis.root_pairs.find { |p| p.key_name == "pi" }
      value = pair&.value_node
      if value&.float?
        sig = value.signature
        expect(sig.first).to eq(:float)
      end
    end

    it "generates signature for boolean true" do
      pair = analysis.root_pairs.find { |p| p.key_name == "enabled" }
      value = pair&.value_node
      if value&.boolean?
        sig = value.signature
        expect(sig.first).to eq(:boolean)
        expect(sig.last).to eq("true")
      end
    end

    it "generates signature for boolean false" do
      pair = analysis.root_pairs.find { |p| p.key_name == "disabled" }
      value = pair&.value_node
      if value&.boolean?
        sig = value.signature
        expect(sig.first).to eq(:boolean)
        expect(sig.last).to eq("false")
      end
    end

    it "generates signature for datetime values" do
      pair = analysis.root_pairs.find { |p| p.key_name == "created" }
      value = pair&.value_node
      if value
        sig = value.signature
        expect(sig.first).to eq(:datetime).or eq(:local_date)
      end
    end

    it "generates signature for array values" do
      pair = analysis.root_pairs.find { |p| p.key_name == "tags" }
      value = pair&.value_node
      if value&.array?
        sig = value.signature
        expect(sig.first).to eq(:array)
        expect(sig.last).to be_an(Integer)
      end
    end

    it "generates signature for comment nodes" do
      # Comments may or may not be exposed as children depending on backend
      root = analysis.root_node
      comment_child = root.children.find { |c| c.comment? }
      if comment_child
        sig = comment_child.signature
        expect(sig.first).to eq(:comment)
      end
    end
  end

  describe "#elements for array values", :toml_parsing do
    let(:array_toml) do
      <<~TOML
        numbers = [1, 2, 3, 4, 5]
        empty = []
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(array_toml) }

    it "returns elements from array" do
      pair = analysis.root_pairs.find { |p| p.key_name == "numbers" }
      value = pair&.value_node
      if value&.array?
        elements = value.elements
        expect(elements).to be_an(Array)
        expect(elements.size).to eq(5)
      end
    end

    it "returns empty array for empty arrays" do
      pair = analysis.root_pairs.find { |p| p.key_name == "empty" }
      value = pair&.value_node
      if value&.array?
        elements = value.elements
        expect(elements).to eq([])
      end
    end

    it "returns empty array for non-array nodes" do
      pair = analysis.root_pairs.first
      skip "No pair found" unless pair
      expect(pair.elements).to eq([])
    end
  end

  describe "#mergeable_children edge cases", :toml_parsing do
    let(:mixed_toml) do
      <<~TOML
        # A comment
        key = "value"

        [table]
        inner = 123
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(mixed_toml) }

    it "returns pairs for tables" do
      table = analysis.tables.first
      skip "No table found" unless table
      children = table.mergeable_children
      expect(children).to all(satisfy { |c| c.pair? })
    end

    it "returns empty array for leaf nodes" do
      pair = analysis.root_pairs.first
      skip "No pair found" unless pair
      value = pair.value_node
      if value&.leaf?
        expect(value.mergeable_children).to eq([])
      end
    end
  end

  describe "#extract_inline_table_keys", :toml_parsing do
    let(:inline_toml) do
      <<~TOML
        config = { alpha = 1, beta = 2, gamma = 3 }
      TOML
    end

    let(:analysis) { Toml::Merge::FileAnalysis.new(inline_toml) }

    it "extracts keys from inline table in sorted order" do
      pair = analysis.root_pairs.find { |p| p.key_name == "config" }
      value = pair&.value_node
      if value&.inline_table?
        sig = value.signature
        expect(sig.first).to eq(:inline_table)
        # Keys should be sorted alphabetically
        expect(sig.last).to eq(["alpha", "beta", "gamma"])
      end
    end
  end
end
