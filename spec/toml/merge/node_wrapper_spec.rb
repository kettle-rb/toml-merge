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
    # These tests would require actual tree-sitter parsing
    # They serve as documentation for expected behavior

    it "generates signatures for table nodes" do
      # A table like [server] should have signature "table:server"
      pending "Requires tree-sitter TOML parser"
      raise "Not implemented"
    end

    it "generates signatures for pair nodes" do
      # A pair like port = 8080 should have signature "pair:port"
      pending "Requires tree-sitter TOML parser"
      raise "Not implemented"
    end

    it "generates signatures for array of tables" do
      # An array like [[servers]] should have signature "table_array:servers"
      pending "Requires tree-sitter TOML parser"
      raise "Not implemented"
    end
  end
end
