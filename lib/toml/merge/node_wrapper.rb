# frozen_string_literal: true

module Toml
  module Merge
    # Wraps tree-sitter nodes with comment associations, line information, and signatures.
    # This provides a unified interface for working with TOML AST nodes during merging.
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = TreeHaver::Language.toml
    #   tree = parser.parse(source)
    #   wrapper = NodeWrapper.new(tree.root_node, lines: source.lines, source: source)
    #   wrapper.signature # => [:table, "section"]
    class NodeWrapper
      class << self
        # Wrap a tree-sitter node, returning nil for nil input.
        #
        # @param node [TreeHaver::Node, nil] tree-sitter node to wrap
        # @param lines [Array<String>] Source lines for content extraction
        # @param source [String, nil] Original source string
        # @param leading_comments [Array<Hash>] Comments before this node
        # @param inline_comment [Hash, nil] Inline comment on the node's line
        # @param backend [Symbol] The backend used for parsing (:tree_sitter_toml or :citrus_toml)
        # @return [NodeWrapper, nil] Wrapped node or nil if node is nil
        def wrap(node, lines, source: nil, leading_comments: [], inline_comment: nil, backend: :tree_sitter_toml)
          return if node.nil?

          new(
            node,
            lines: lines,
            source: source,
            leading_comments: leading_comments,
            inline_comment: inline_comment,
            backend: backend,
          )
        end
      end

      # @return [TreeHaver::Node] The wrapped tree-sitter node
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

      # @return [Symbol] The backend used for parsing
      attr_reader :backend

      # @return [TreeHaver::Node, nil] The document root node for sibling lookups
      attr_reader :document_root

      # @param node [TreeHaver::Node] tree-sitter node to wrap
      # @param lines [Array<String>] Source lines for content extraction
      # @param source [String] Original source string for byte-based text extraction
      # @param leading_comments [Array<Hash>] Comments before this node
      # @param inline_comment [Hash, nil] Inline comment on the node's line
      # @param backend [Symbol] The backend used for parsing (:tree_sitter_toml or :citrus_toml)
      # @param document_root [TreeHaver::Node, nil] The document root for sibling lookups (Citrus normalization)
      def initialize(node, lines:, source: nil, leading_comments: [], inline_comment: nil,
        backend: :tree_sitter_toml, document_root: nil)
        @node = node
        @lines = lines
        @source = source || lines.join("\n")
        @leading_comments = leading_comments
        @inline_comment = inline_comment
        @backend = backend
        @document_root = document_root

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

      # Get the canonical (normalized) type for this node
      # @return [Symbol]
      def canonical_type
        NodeTypeNormalizer.canonical_type(@node.type, @backend)
      end

      # Check if this node has a specific type (checks both raw and canonical)
      # @param type_name [Symbol, String] Type to check
      # @return [Boolean]
      def type?(type_name)
        type_sym = type_name.to_sym
        @node.type.to_sym == type_sym || canonical_type == type_sym
      end

      # Check if this is a TOML table (section)
      # @return [Boolean]
      def table?
        canonical_type == :table
      end

      # Check if this is a TOML array of tables
      # Uses NodeTypeNormalizer for backend-agnostic type checking.
      # @return [Boolean]
      def array_of_tables?
        canonical_type == :array_of_tables
      end

      # Check if this is a TOML inline table
      # @return [Boolean]
      def inline_table?
        canonical_type == :inline_table
      end

      # Check if this is a TOML array
      # @return [Boolean]
      def array?
        canonical_type == :array
      end

      # Check if this is a TOML string
      # @return [Boolean]
      def string?
        canonical_type == :string
      end

      # Check if this is a TOML integer
      # @return [Boolean]
      def integer?
        canonical_type == :integer
      end

      # Check if this is a TOML float
      # @return [Boolean]
      def float?
        canonical_type == :float
      end

      # Check if this is a TOML boolean
      # @return [Boolean]
      def boolean?
        canonical_type == :boolean
      end

      # Check if this is a key-value pair
      # @return [Boolean]
      def pair?
        canonical_type == :pair
      end

      # Check if this is a comment
      # @return [Boolean]
      def comment?
        canonical_type == :comment
      end

      # Check if this is a datetime
      # @return [Boolean]
      def datetime?
        canonical_type == :datetime
      end

      # Get the table name (header) if this is a table
      # @return [String, nil]
      def table_name
        return unless table? || array_of_tables?

        # Find the dotted_key or bare_key child that represents the table name
        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          if NodeTypeNormalizer.key_type?(child_canonical)
            return node_text(child)
          end
        end
        nil
      end

      # Get the key name if this is a pair node
      # @return [String, nil]
      def key_name
        return unless pair?

        # In TOML, pair has key children (bare_key, quoted_key, or dotted_key)
        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          if NodeTypeNormalizer.key_type?(child_canonical)
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
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          # Skip keys and equals sign, get the value
          next if NodeTypeNormalizer.key_type?(child_canonical)
          next if child_canonical == :equals

          return NodeWrapper.new(child, lines: @lines, source: @source, backend: @backend,
            document_root: @document_root)
        end
        nil
      end

      # Get key-value pairs from a table or inline_table.
      #
      # Handles structural differences between backends:
      # - Tree-sitter: pairs are children of the table node
      # - Citrus: pairs are siblings at document level (table only contains header)
      #
      # For Citrus backend, when no pair children are found, we look for sibling
      # pairs in the document that belong to this table (pairs after this table's
      # header but before the next table).
      #
      # @return [Array<NodeWrapper>]
      def pairs
        return [] unless table? || inline_table? || document? || array_of_tables?

        # First, try to find pairs as direct children (tree-sitter structure)
        result = collect_child_pairs
        return result if result.any?

        # For Citrus backend: pairs are siblings, not children
        # Look for pairs in document that belong to this table
        return [] unless @document_root && (table? || array_of_tables?)

        collect_sibling_pairs_for_table
      end

      # Check if this is the document root
      # @return [Boolean]
      def document?
        canonical_type == :document
      end

      # Get array elements if this is an array
      # @return [Array<NodeWrapper>]
      def elements
        return [] unless array?

        result = []
        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type)
          # Skip punctuation and comments
          next if child_canonical == :comment
          next if %i[comma bracket_open bracket_close].include?(child_canonical)

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
        case canonical_type
        when :table, :inline_table, :array_of_tables
          pairs
        when :array
          elements
        when :document
          # Return top-level pairs and tables
          result = []
          @node.each do |child|
            child_canonical = NodeTypeNormalizer.canonical_type(child.type)
            next if child_canonical == :comment

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
      # @param ts_node [TreeHaver::Node] The tree-sitter node
      # @return [String]
      def node_text(ts_node)
        return "" unless ts_node.respond_to?(:start_byte) && ts_node.respond_to?(:end_byte)

        @source[ts_node.start_byte...ts_node.end_byte] || ""
      end

      # Get the content for this node from source lines.
      #
      # Handles structural differences between backends:
      # - Tree-sitter: table nodes include pairs, so start_line..end_line covers everything
      # - Citrus: table nodes only include header, so we extend to include associated pairs
      #
      # @return [String]
      def content
        return "" unless @start_line

        # For tables with Citrus backend, extend end_line to include pairs
        effective_end = effective_end_line
        return "" unless effective_end

        (@start_line..effective_end).map { |ln| @lines[ln - 1] }.compact.join("\n")
      end

      # Get the effective end line for this node, accounting for Citrus backend.
      # For Citrus tables, this extends to the line before the next table.
      # @return [Integer, nil]
      def effective_end_line
        return @end_line unless (table? || array_of_tables?) && @document_root

        # Check if we have pairs as children (tree-sitter structure)
        child_pairs = collect_child_pairs
        return @end_line if child_pairs.any?

        # Citrus structure: find the last pair that belongs to us
        sibling_pairs = collect_sibling_pairs_for_table
        return @end_line if sibling_pairs.empty?

        # Return the end line of the last pair
        sibling_pairs.map(&:end_line).compact.max || @end_line
      end

      # String representation for debugging
      # @return [String]
      def inspect
        "#<#{self.class.name} type=#{@node.type} lines=#{@start_line}..#{@end_line}>"
      end

      private

      def compute_signature(node)
        # Use canonical type for signature generation
        canonical = NodeTypeNormalizer.canonical_type(node.type)

        case canonical
        when :document
          # Root document
          [:document]
        when :table
          # Tables identified by their header name
          name = table_name
          [:table, name]
        when :array_of_tables
          # Array of tables identified by their header name
          name = table_name
          [:array_of_tables, name]
        when :pair
          # Pairs identified by their key name
          key = key_name
          [:pair, key]
        when :inline_table
          # Inline tables identified by their keys
          keys = extract_inline_table_keys(node)
          [:inline_table, keys.sort]
        when :array
          # Arrays identified by their length
          elements_count = 0
          node.each { |c| elements_count += 1 unless %i[comment comma bracket_open bracket_close].include?(NodeTypeNormalizer.canonical_type(c.type)) }
          [:array, elements_count]
        when :string
          # Strings identified by their content
          [:string, node_text(node)]
        when :integer
          # Integers identified by their value
          [:integer, node_text(node)]
        when :float
          # Floats identified by their value
          [:float, node_text(node)]
        when :boolean
          # Booleans
          [:boolean, node_text(node)]
        when :datetime
          # Datetime values
          [:datetime, node_text(node)]
        when :comment
          # Comments identified by their content
          [:comment, node_text(node)&.strip]
        else
          # Generic fallback - use canonical type in signature
          content_preview = node_text(node)&.slice(0, 50)&.strip
          [canonical, content_preview]
        end
      end

      def extract_inline_table_keys(inline_table_node)
        keys = []
        inline_table_node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type)
          next unless child_canonical == :pair

          child.each do |pair_child|
            pair_child_canonical = NodeTypeNormalizer.canonical_type(pair_child.type)
            if NodeTypeNormalizer.key_type?(pair_child_canonical)
              key_text = node_text(pair_child)&.gsub(/\A["']|["']\z/, "")
              keys << key_text if key_text
              break
            end
          end
        end
        keys
      end

      # Collect pairs that are direct children of this node.
      # This is the standard tree-sitter structure.
      # @return [Array<NodeWrapper>]
      def collect_child_pairs
        result = []
        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          next unless child_canonical == :pair

          result << NodeWrapper.new(child, lines: @lines, source: @source, backend: @backend,
            document_root: @document_root)
        end
        result
      end

      # Collect pairs from document siblings that belong to this table.
      # Used for Citrus backend where pairs are siblings, not children.
      #
      # A pair belongs to this table if:
      # - It appears after this table's header line
      # - It appears before the next table's header line (or end of document)
      #
      # @return [Array<NodeWrapper>]
      def collect_sibling_pairs_for_table
        result = []
        my_start = @start_line
        return result unless my_start

        # Find the next table's start line (to know where our pairs end)
        next_table_start = find_next_table_start_line

        # Iterate through document children to find pairs in our range
        @document_root.each do |sibling|
          sibling_canonical = NodeTypeNormalizer.canonical_type(sibling.type, @backend)
          next unless sibling_canonical == :pair

          sibling_start = sibling.respond_to?(:start_point) ? sibling.start_point.row + 1 : nil
          next unless sibling_start

          # Pair must be after our header
          next unless sibling_start > my_start

          # Pair must be before the next table (if there is one)
          next if next_table_start && sibling_start >= next_table_start

          result << NodeWrapper.new(sibling, lines: @lines, source: @source, backend: @backend,
            document_root: @document_root)
        end

        result
      end

      # Find the start line of the next table in the document.
      # Returns nil if this is the last table.
      # @return [Integer, nil]
      def find_next_table_start_line
        return nil unless @document_root

        my_start = @start_line
        next_table_start = nil

        @document_root.each do |sibling|
          sibling_canonical = NodeTypeNormalizer.canonical_type(sibling.type, @backend)
          next unless NodeTypeNormalizer.table_type?(sibling_canonical)

          sibling_start = sibling.respond_to?(:start_point) ? sibling.start_point.row + 1 : nil
          next unless sibling_start
          next unless sibling_start > my_start

          # Found a table after us - track the closest one
          if next_table_start.nil? || sibling_start < next_table_start
            next_table_start = sibling_start
          end
        end

        next_table_start
      end
    end
  end
end
