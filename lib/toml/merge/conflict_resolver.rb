# frozen_string_literal: true

module Toml
  module Merge
    # Resolves conflicts between template and destination TOML content
    # using structural signatures and configurable preferences.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    class ConflictResolver < Ast::Merge::ConflictResolverBase
      # Creates a new ConflictResolver
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      # @param preference [Symbol] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false, match_refiner: nil, **options)
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          match_refiner: match_refiner,
          **options
        )
        @emitter = Emitter.new
      end

      protected

      # Resolve conflicts and populate the result using tree-based merging
      #
      # @param result [MergeResult] Result object to populate
      def resolve_batch(result)
        DebugLogger.time("ConflictResolver#resolve") do
          template_statements = @template_analysis.statements
          dest_statements = @dest_analysis.statements

          # Clear emitter for fresh merge
          @emitter.clear

          # Merge root-level statements via emitter
          merge_node_lists_to_emitter(
            template_statements,
            dest_statements,
            @template_analysis,
            @dest_analysis,
          )

          # Transfer emitter output to result
          emitted_content = @emitter.to_s
          unless emitted_content.empty?
            emitted_content.lines.each do |line|
              result.add_line(line.chomp, decision: MergeResult::DECISION_MERGED, source: :merged)
            end
          end

          DebugLogger.debug("Conflict resolution complete", {
            template_statements: template_statements.size,
            dest_statements: dest_statements.size,
            result_lines: result.line_count,
          })
        end
      end

      private

      # Recursively merge two lists of nodes, emitting to emitter
      # @param template_nodes [Array<NodeWrapper>] Template nodes
      # @param dest_nodes [Array<NodeWrapper>] Destination nodes
      # @param template_analysis [FileAnalysis] Template analysis for line access
      # @param dest_analysis [FileAnalysis] Destination analysis for line access
      def merge_node_lists_to_emitter(template_nodes, dest_nodes, template_analysis, dest_analysis)
        # Build signature maps for matching
        template_by_sig = build_signature_map(template_nodes, template_analysis)
        dest_by_sig = build_signature_map(dest_nodes, dest_analysis)

        # Build refined matches for nodes that don't match by signature
        refined_matches = build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        refined_dest_to_template = refined_matches.invert

        # Track which nodes have been processed
        processed_template_sigs = ::Set.new
        processed_dest_sigs = ::Set.new

        # First pass: Process destination nodes
        dest_nodes.each do |dest_node|
          dest_sig = dest_analysis.generate_signature(dest_node)

          # Check for signature match
          if dest_sig && template_by_sig[dest_sig]
            template_info = template_by_sig[dest_sig].first
            template_node = template_info[:node]

            # Both have this node - merge them
            merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)

            processed_dest_sigs << dest_sig
            processed_template_sigs << dest_sig
          elsif refined_dest_to_template.key?(dest_node)
            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = template_analysis.generate_signature(template_node)

            # Merge matched nodes
            merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)

            processed_dest_sigs << dest_sig if dest_sig
            processed_template_sigs << template_sig if template_sig
          else
            # Destination-only node - always keep
            emit_node(dest_node, dest_analysis)
            processed_dest_sigs << dest_sig if dest_sig
          end
        end

        # Second pass: Add template-only nodes if configured
        return unless @add_template_only_nodes

        template_nodes.each do |template_node|
          template_sig = template_analysis.generate_signature(template_node)

          # Skip if already processed
          next if template_sig && processed_template_sigs.include?(template_sig)

          # Add template-only node
          emit_node(template_node, template_analysis)
          processed_template_sigs << template_sig if template_sig
        end
      end

      # Merge two matched nodes
      # @param template_node [NodeWrapper] Template node
      # @param dest_node [NodeWrapper] Destination node
      # @param template_analysis [FileAnalysis] Template analysis
      # @param dest_analysis [FileAnalysis] Destination analysis
      def merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
        # For TOML, tables can be merged recursively
        if dest_node.table? && template_node.table?
          # Emit table header and merge children
          @emitter.emit_table_header(dest_node.table_name || template_node.table_name)

          template_children = template_node.children
          dest_children = dest_node.children

          merge_node_lists_to_emitter(
            template_children,
            dest_children,
            template_analysis,
            dest_analysis,
          )
        elsif @preference == :destination
          # Leaf nodes or mismatched types - use preference
          emit_node(dest_node, dest_analysis)
        else
          emit_node(template_node, template_analysis)
        end
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis)
        # Emit the node content
        if node.start_line && node.end_line
          lines = []
          (node.start_line..node.end_line).each do |line_num|
            line = analysis.line_at(line_num)
            lines << line if line
          end
          @emitter.emit_raw_lines(lines)
        end
      end

      # Build a map of refined matches
      # @param template_nodes [Array<NodeWrapper>] Template nodes
      # @param dest_nodes [Array<NodeWrapper>] Destination nodes
      # @param template_by_sig [Hash] Template signature map
      # @param dest_by_sig [Hash] Destination signature map
      # @return [Hash] Map of template_node => dest_node
      def build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        return {} unless @match_refiner

        # Find unmatched nodes
        matched_sigs = template_by_sig.keys & dest_by_sig.keys
        unmatched_t_nodes = template_nodes.reject do |n|
          sig = @template_analysis.generate_signature(n)
          sig && matched_sigs.include?(sig)
        end
        unmatched_d_nodes = dest_nodes.reject do |n|
          sig = @dest_analysis.generate_signature(n)
          sig && matched_sigs.include?(sig)
        end

        return {} if unmatched_t_nodes.empty? || unmatched_d_nodes.empty?

        # Call the refiner
        matches = @match_refiner.call(unmatched_t_nodes, unmatched_d_nodes, {
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        })

        # Build result map: template node -> dest node
        matches.each_with_object({}) do |match, h|
          h[match.template_node] = match.dest_node
        end
      end
    end
  end
end
