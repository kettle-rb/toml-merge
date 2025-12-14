# frozen_string_literal: true

module Toml
  module Merge
    # Wraps tree-sitter nodes with comment associations, line information, and signatures.
    # This provides a unified interface for working with TOML AST nodes during merging.
    #
    # @example Basic usage
    #   parser = TreeSitter::Parser.new
    #   parser.language = TreeSitter::Language.load("toml", path)
    #   tree = parser.parse_string(nil, source)
    #   wrapper = NodeWrapper.new(tree.root_node, lines: source.lines, source: source)
    #   wrapper.signature # => [:table, "section"]
    class NodeWrapper
      class << self
        # Wrap a tree-sitter node, returning nil for nil input.
        #
        # @param node [TreeSitter::Node, nil] Tree-sitter node to wrap
        # @param lines [Array<String>] Source lines for content extraction
        # @param source [String, nil] Original source string
        # @param leading_comments [Array<Hash>] Comments before this node
        # @param inline_comment [Hash, nil] Inline comment on the node's line
        # @return [NodeWrapper, nil] Wrapped node or nil if node is nil
        def wrap(node, lines, source: nil, leading_comments: [], inline_comment: nil)
          return if node.nil?

          new(node, lines: lines, source: source, leading_comments: leading_comments, inline_comment: inline_comment)
        end
      end

      # @return [TreeSitter::Node] The wrapped tree-sitter node
      attr_reader :node

      # @return [Array<Hash>] Leading comments associated with this node
      attr_reader :leading_comments

      # @return [String] The original source string
      attr_reader :source

      # @return [Hash, nil] Inline/trailing comment on the same line
      attr_reader :inline_comment

      # @return [Integer] Start line (1-based)
      attr_reader :start_line

      # @return [Integer] End line (1-based)
      attr_reader :end_line

      # @return [Array<String>] Source lines
      attr_reader :lines

      # @param node [TreeSitter::Node] Tree-sitter node to wrap
      # @param lines [Array<String>] Source lines for content extraction
      # @param source [String] Original source string for byte-based text extraction
      # @param leading_comments [Array<Hash>] Comments before this node
      # @param inline_comment [Hash, nil] Inline comment on the node's line
      def initialize(node, lines:, source: nil, leading_comments: [], inline_comment: nil)
        @node = node
        @lines = lines
        @source = source || lines.join("\n")
        @leading_comments = leading_comments
        @inline_comment = inline_comment

        # Extract line information from the tree-sitter node (0-indexed to 1-indexed)
        @start_line = node.start_point.row + 1 if node.respond_to?(:start_point)
        @end_line = node.end_point.row + 1 if node.respond_to?(:end_point)

        # Handle edge case where end_line might be before start_line
        @end_line = @start_line if @start_line && @end_line && @end_line < @start_line
      end

      # Generate a signature for this node for matching purposes.
      # Signatures are used to identify corresponding nodes between template and destination.
      #
      # @return [Array, nil] Signature array or nil if not signaturable
      def signature
        compute_signature(@node)
      end

      # Get the node type as a symbol
      # @return [Symbol]
      def type
        @node.type.to_sym
      end

      # Check if this node has a specific type
      # @param type_name [Symbol, String] Type to check
      # @return [Boolean]
      def type?(type_name)
        @node.type.to_s == type_name.to_s
      end

      # Check if this is a TOML table (section)
      # @return [Boolean]
      def table?
        @node.type.to_s == "table"
      end

      # Check if this is a TOML array of tables
      # @return [Boolean]
      def array_of_tables?
        type_str = @node.type.to_s
        type_str == "array_of_tables" || type_str == "table_array_element"
      end

      # Check if this is a TOML inline table
      # @return [Boolean]
      def inline_table?
        @node.type.to_s == "inline_table"
      end

      # Check if this is a TOML array
      # @return [Boolean]
      def array?
        @node.type.to_s == "array"
      end

      # Check if this is a TOML string
      # @return [Boolean]
      def string?
        %w[string basic_string literal_string multiline_basic_string multiline_literal_string].include?(@node.type.to_s)
      end

      # Check if this is a TOML integer
      # @return [Boolean]
      def integer?
        @node.type.to_s == "integer"
      end

      # Check if this is a TOML float
      # @return [Boolean]
      def float?
        @node.type.to_s == "float"
      end

      # Check if this is a TOML boolean
      # @return [Boolean]
      def boolean?
        @node.type.to_s == "boolean"
      end

      # Check if this is a key-value pair
      # @return [Boolean]
      def pair?
        @node.type.to_s == "pair"
      end

      # Check if this is a comment
      # @return [Boolean]
      def comment?
        @node.type.to_s == "comment"
      end

      # Check if this is a datetime
      # @return [Boolean]
      def datetime?
        %w[offset_date_time local_date_time local_date local_time].include?(@node.type.to_s)
      end

      # Get the table name (header) if this is a table
      # @return [String, nil]
      def table_name
        return unless table? || array_of_tables?

        # Find the dotted_key or bare_key child that represents the table name
        @node.each do |child|
          child_type = child.type.to_s
          if %w[dotted_key bare_key quoted_key].include?(child_type)
            return node_text(child)
          end
        end
        nil
      end

      # Get the key name if this is a pair node
      # @return [String, nil]
      def key_name
        return unless pair?

        # In TOML tree-sitter, pair has key children (bare_key, quoted_key, or dotted_key)
        @node.each do |child|
          child_type = child.type.to_s
          if %w[bare_key quoted_key dotted_key].include?(child_type)
            key_text = node_text(child)
            # Remove surrounding quotes if present
            return key_text&.gsub(/\A["']|["']\z/, "")
          end
        end
        nil
      end

      # Get the value node if this is a pair
      # @return [NodeWrapper, nil]
      def value_node
        return unless pair?

        @node.each do |child|
          child_type = child.type.to_s
          # Skip keys, get the value
          next if %w[bare_key quoted_key dotted_key =].include?(child_type)

          return NodeWrapper.new(child, lines: @lines, source: @source)
        end
        nil
      end

      # Get key-value pairs from a table or inline_table
      # @return [Array<NodeWrapper>]
      def pairs
        return [] unless table? || inline_table? || document?

        result = []
        @node.each do |child|
          next unless child.type.to_s == "pair"

          result << NodeWrapper.new(child, lines: @lines, source: @source)
        end
        result
      end

      # Check if this is the document root
      # @return [Boolean]
      def document?
        @node.type.to_s == "document"
      end

      # Get array elements if this is an array
      # @return [Array<NodeWrapper>]
      def elements
        return [] unless array?

        result = []
        @node.each do |child|
          child_type = child.type.to_s
          # Skip punctuation and comments
          next if child_type == "comment"
          next if %w[, \[ \]].include?(child_type)

          result << NodeWrapper.new(child, lines: @lines, source: @source)
        end
        result
      end

      # Get children wrapped as NodeWrappers
      # @return [Array<NodeWrapper>]
      def children
        return [] unless @node.respond_to?(:each)

        result = []
        @node.each do |child|
          result << NodeWrapper.new(child, lines: @lines, source: @source)
        end
        result
      end

      # Get mergeable children - the semantically meaningful children for tree merging
      # For tables, returns pairs. For arrays, returns elements.
      # For other node types, returns empty array (leaf nodes).
      # @return [Array<NodeWrapper>]
      def mergeable_children
        case type
        when :table, :inline_table
          pairs
        when :array
          elements
        when :document
          # Return top-level pairs and tables
          result = []
          @node.each do |child|
            child_type = child.type.to_s
            next if child_type == "comment"

            result << NodeWrapper.new(child, lines: @lines, source: @source)
          end
          result
        else
          []
        end
      end

      # Check if this node is a container (has mergeable children)
      # @return [Boolean]
      def container?
        table? || array_of_tables? || inline_table? || array? || document?
      end

      # Check if this node is a leaf (no mergeable children)
      # @return [Boolean]
      def leaf?
        !container?
      end

      # Get the opening line for a table (the line with [table_name])
      # @return [String, nil]
      def opening_line
        return unless @start_line
        return unless table? || array_of_tables?

        @lines[@start_line - 1]
      end

      # Get the closing line for a container node
      # For tables, this is the last line of content before the next table or EOF
      # @return [String, nil]
      def closing_line
        return unless container? && @end_line

        @lines[@end_line - 1]
      end

      # Get the text content for this node by extracting from source using byte positions
      # @return [String]
      def text
        node_text(@node)
      end

      # Extract text from a tree-sitter node using byte positions
      # @param ts_node [TreeSitter::Node] The tree-sitter node
      # @return [String]
      def node_text(ts_node)
        return "" unless ts_node.respond_to?(:start_byte) && ts_node.respond_to?(:end_byte)

        @source[ts_node.start_byte...ts_node.end_byte] || ""
      end

      # Get the content for this node from source lines
      # @return [String]
      def content
        return "" unless @start_line && @end_line

        (@start_line..@end_line).map { |ln| @lines[ln - 1] }.compact.join("\n")
      end

      # String representation for debugging
      # @return [String]
      def inspect
        "#<#{self.class.name} type=#{@node.type} lines=#{@start_line}..#{@end_line}>"
      end

      private

      def compute_signature(node)
        node_type = node.type.to_s

        case node_type
        when "document"
          # Root document
          [:document]
        when "table"
          # Tables identified by their header name
          name = table_name
          [:table, name]
        when "array_of_tables", "table_array_element"
          # Array of tables identified by their header name
          name = table_name
          [:array_of_tables, name]
        when "pair"
          # Pairs identified by their key name
          key = key_name
          [:pair, key]
        when "inline_table"
          # Inline tables identified by their keys
          keys = extract_inline_table_keys(node)
          [:inline_table, keys.sort]
        when "array"
          # Arrays identified by their length
          elements_count = 0
          node.each do |c|
            next if %w[comment , \[ \]].include?(c.type.to_s)

            elements_count += 1
          end
          [:array, elements_count]
        when "string", "basic_string", "literal_string", "multiline_basic_string", "multiline_literal_string"
          # Strings identified by their content
          [:string, node_text(node)]
        when "integer"
          # Integers identified by their value
          [:integer, node_text(node)]
        when "float"
          # Floats identified by their value
          [:float, node_text(node)]
        when "boolean"
          # Booleans
          [:boolean, node_text(node)]
        when "offset_date_time", "local_date_time", "local_date", "local_time"
          # Datetime values
          [:datetime, node_text(node)]
        when "comment"
          # Comments identified by their content
          [:comment, node_text(node)&.strip]
        else
          # Generic fallback
          content_preview = node_text(node)&.slice(0, 50)&.strip
          [node_type.to_sym, content_preview]
        end
      end

      def extract_inline_table_keys(inline_table_node)
        keys = []
        inline_table_node.each do |child|
          next unless child.type.to_s == "pair"

          child.each do |pair_child|
            child_type = pair_child.type.to_s
            if %w[bare_key quoted_key dotted_key].include?(child_type)
              key_text = node_text(pair_child)&.gsub(/\A["']|["']\z/, "")
              keys << key_text if key_text
              break
            end
          end
        end
        keys
      end
    end
  end
end
