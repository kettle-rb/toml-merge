# frozen_string_literal: true

module Toml
  module Merge
    # Analyzes TOML file structure, extracting statements for merging.
    # This is the main analysis class that prepares TOML content for merging.
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(toml_source)
    #   analysis.valid? # => true
    #   analysis.statements # => [NodeWrapper, ...]
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # @return [TreeHaver::Tree, nil] Parsed AST
      attr_reader :ast

      # @return [Array] Parse errors if any
      attr_reader :errors

      class << self
        # Find the parser library path using TreeHaver::GrammarFinder
        #
        # @return [String, nil] Path to the parser library or nil if not found
        def find_parser_path
          TreeHaver::GrammarFinder.new(:toml).find_library_path
        end
      end

      # Initialize file analysis
      #
      # @param source [String] TOML source code to analyze
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param parser_path [String, nil] Path to tree-sitter-toml parser library
      # @param options [Hash] Additional options (forward compatibility - freeze_token, node_typing, etc.)
      def initialize(source, signature_generator: nil, parser_path: nil, **options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @signature_generator = signature_generator
        @parser_path = parser_path || self.class.find_parser_path
        @errors = []
        # **options captures any additional parameters (e.g., freeze_token, node_typing) for forward compatibility

        # Parse the TOML
        DebugLogger.time("FileAnalysis#parse_toml") { parse_toml }

        @statements = integrate_nodes

        DebugLogger.debug("FileAnalysis initialized", {
          signature_generator: signature_generator ? "custom" : "default",
          statements_count: @statements.size,
          valid: valid?,
        })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @errors.empty? && !@ast.nil?
      end

      # Override to detect tree-sitter nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(NodeWrapper) || super
      end

      # Get the root node of the parse tree
      # @return [NodeWrapper, nil]
      def root_node
        return unless valid?

        NodeWrapper.new(@ast.root_node, lines: @lines, source: @source)
      end

      # Get a hash mapping signatures to nodes
      # @return [Hash<Array, NodeWrapper>]
      def signature_map
        @signature_map ||= build_signature_map
      end

      # Get all top-level tables (sections) in the TOML document
      # Uses NodeTypeNormalizer for backend-agnostic type checking.
      # @return [Array<NodeWrapper>]
      def tables
        return [] unless valid?

        result = []
        @ast.root_node.each do |child|
          canonical_type = NodeTypeNormalizer.canonical_type(child.type)
          next unless NodeTypeNormalizer.table_type?(canonical_type)

          result << NodeWrapper.new(child, lines: @lines, source: @source)
        end
        result
      end

      # Get all top-level key-value pairs (not in tables)
      # @return [Array<NodeWrapper>]
      def root_pairs
        return [] unless valid?

        result = []
        @ast.root_node.each do |child|
          canonical_type = NodeTypeNormalizer.canonical_type(child.type)
          next unless canonical_type == :pair

          result << NodeWrapper.new(child, lines: @lines, source: @source)
        end
        result
      end

      private

      def parse_toml
        begin
          # Use TreeHaver's high-level API - it handles:
          # - Grammar auto-discovery (tree-sitter or Citrus)
          # - Backend selection
          # - Fallback to Citrus if tree-sitter unavailable
          parser = TreeHaver.parser_for(:toml,
            library_path: @parser_path,
            citrus_config: {
              gem_name: "toml-rb",
              grammar_const: "TomlRB::Document",
            },
          )

          @ast = parser.parse(@source)

          # Check for parse errors in the tree
          if @ast&.root_node&.has_error?
            collect_parse_errors(@ast.root_node)
            # Don't raise here - let SmartMergerBase detect via valid? check
            # This is consistent with how other FileAnalysis classes handle parse errors
          end
        rescue TreeHaver::NotAvailable => e
          @errors << e.message
          @ast = nil
        rescue StandardError => e
          @errors << e unless @errors.include?(e)
          @ast = nil
        end
      end

      def collect_parse_errors(node)
        # Collect ERROR and MISSING nodes from the tree
        if node.type.to_s == "ERROR" || node.missing?
          @errors << {
            type: node.type.to_s,
            start_point: node.start_point,
            end_point: node.end_point,
            text: node.to_s,
          }
        end

        node.each { |child| collect_parse_errors(child) }
      end

      def integrate_nodes
        return [] unless valid?

        result = []
        root = @ast.root_node
        return result unless root

        # Return all root-level nodes (document children)
        # For TOML, this includes tables, array_of_tables, and top-level pairs
        root.each do |child|
          # Skip comments (handled separately)
          canonical_type = NodeTypeNormalizer.canonical_type(child.type)
          next if canonical_type == :comment

          wrapper = NodeWrapper.new(child, lines: @lines, source: @source)
          next unless wrapper.start_line && wrapper.end_line

          result << wrapper
        end

        # Sort by start line
        result.sort_by { |node| node.start_line || 0 }
      end

      def compute_node_signature(node)
        return unless node.is_a?(NodeWrapper)

        node.signature
      end

      def build_signature_map
        map = {}
        statements.each do |node|
          sig = generate_signature(node)
          map[sig] = node if sig
        end
        map
      end
    end
  end
end
