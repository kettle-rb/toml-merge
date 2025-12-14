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

      # @return [TreeSitter::Tree, nil] Parsed AST
      attr_reader :ast

      # @return [Array] Parse errors if any
      attr_reader :errors

      class << self
        # Find the parser library path
        #
        # Uses TreeHaver::GrammarFinder if available, otherwise
        # searches common paths directly.
        #
        # @return [String, nil] Path to the parser library or nil if not found
        def find_parser_path
          # Use TreeHaver's GrammarFinder if available
          if defined?(TreeHaver::GrammarFinder)
            TreeHaver::GrammarFinder.new(:toml).find_library_path
          else
            # Fallback: check environment variable first
            env_path = ENV["TREE_SITTER_TOML_PATH"]
            return env_path if env_path && File.exist?(env_path)

            # Search common paths
            [
              "/usr/lib/libtree-sitter-toml.so",
              "/usr/lib64/libtree-sitter-toml.so",
              "/usr/local/lib/libtree-sitter-toml.so",
              "/opt/homebrew/lib/libtree-sitter-toml.dylib",
              "/usr/local/lib/libtree-sitter-toml.dylib",
            ].find { |path| File.exist?(path) }
          end
        end
      end

      # Initialize file analysis
      #
      # @param source [String] TOML source code to analyze
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param parser_path [String, nil] Path to tree-sitter-toml parser library
      def initialize(source, signature_generator: nil, parser_path: nil)
        @source = source
        @lines = source.lines.map(&:chomp)
        @signature_generator = signature_generator
        @parser_path = parser_path || self.class.find_parser_path
        @errors = []

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
      # @return [Array<NodeWrapper>]
      def tables
        return [] unless valid?

        result = []
        @ast.root_node.each do |child|
          child_type = child.type.to_s
          next unless %w[table array_of_tables].include?(child_type)

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
          next unless child.type.to_s == "pair"

          result << NodeWrapper.new(child, lines: @lines, source: @source)
        end
        result
      end

      private

      def parse_toml
        unless @parser_path && File.exist?(@parser_path)
          error_msg = if defined?(TreeHaver::GrammarFinder)
            TreeHaver::GrammarFinder.new(:toml).not_found_message
          else
            "Tree-sitter toml parser not found. Install tree-sitter-toml or set TREE_SITTER_TOML_PATH."
          end
          @errors << error_msg
          @ast = nil
          raise StandardError, error_msg
        end

        begin
          language = TreeSitter::Language.load("toml", @parser_path)
          parser = TreeSitter::Parser.new
          parser.language = language
          @ast = parser.parse_string(nil, @source)

          # Check for parse errors in the tree
          if @ast&.root_node&.has_error?
            collect_parse_errors(@ast.root_node)
            # Raise to allow SmartMergerBase to wrap with appropriate error type
            raise StandardError, "TOML parse error: #{@errors.first}"
          end
        rescue StandardError => e
          @errors << e unless @errors.include?(e)
          @ast = nil
          raise
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
          next if child.type.to_s == "comment"

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
