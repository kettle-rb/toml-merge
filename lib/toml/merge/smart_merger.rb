# frozen_string_literal: true

module Toml
  module Merge
    # High-level merger for TOML content.
    # Orchestrates parsing, analysis, and conflict resolution.
    #
    # @example Basic usage
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #   File.write("merged.toml", result.output)
    #
    # @example With options
    #   merger = SmartMerger.new(template, dest,
    #     preference: :template,
    #     add_template_only_nodes: true)
    #   result = merger.merge
    #
    # @example Enable fuzzy matching
    #   merger = SmartMerger.new(template, dest, match_refiner: TableMatchRefiner.new)
    #
    # @example With regions (embedded content)
    #   merger = SmartMerger.new(template, dest,
    #     regions: [{ detector: SomeDetector.new, merger_class: SomeMerger }])
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      # Creates a new SmartMerger
      #
      # @param template_content [String] Template TOML content
      # @param dest_content [String] Destination TOML content
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :destination, :template, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add nodes only found in template
      # @param freeze_token [String, nil] Token for freeze block markers
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param options [Hash] Additional options for forward compatibility
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        freeze_token: nil,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        **options
      )
        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
        )
      end

      # Backward-compatible options hash
      #
      # @return [Hash] The merge options
      def options
        {
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          match_refiner: @match_refiner,
        }
      end

      protected

      # @return [Class] The analysis class for TOML files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token (not used for TOML)
      def default_freeze_token
        "toml-merge"
      end

      # @return [Class] The resolver class for TOML files
      def resolver_class
        ConflictResolver
      end

      # @return [Class] The result class for TOML files
      def result_class
        MergeResult
      end

      # Perform the TOML-specific merge
      #
      # @return [MergeResult] The merge result
      def perform_merge
        @resolver.resolve(@result)

        DebugLogger.debug("Merge complete", {
          lines: @result.line_count,
          decisions: @result.statistics,
        })

        @result
      end

      # Build the resolver with TOML-specific signature
      def build_resolver
        ConflictResolver.new(
          @template_analysis,
          @dest_analysis,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          match_refiner: @match_refiner,
        )
      end

      # Build the result (no-arg constructor for TOML)
      def build_result
        MergeResult.new
      end

      # @return [Class] The template parse error class for TOML
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for TOML
      def destination_parse_error_class
        DestinationParseError
      end

      private

      # TOML FileAnalysis only accepts signature_generator, not freeze_token
      def build_full_analysis_options
        {signature_generator: @signature_generator}
      end
    end
  end
end
