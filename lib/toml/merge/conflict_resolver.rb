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
      include ::Ast::Merge::TrailingGroups::DestIterate

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
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false, remove_template_missing_nodes: false, match_refiner: nil, **options)
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
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

          if template_statements.empty? && dest_statements.empty?
            emit_comment_only_document(preferred_comment_only_analysis(@template_analysis, @dest_analysis))
            return transfer_emitter_output(result)
          end

          emit_root_boundary_region(preferred_boundary_analysis(@template_analysis, @dest_analysis), :preamble)

          # Merge root-level statements via emitter
          merge_node_lists_to_emitter(
            template_statements,
            dest_statements,
            @template_analysis,
            @dest_analysis,
          )

          emit_root_boundary_region(preferred_boundary_analysis(@template_analysis, @dest_analysis), :postlude)
          emit_comment_only_document(preferred_comment_only_analysis(@template_analysis, @dest_analysis)) if @emitter.to_s.empty?

          # Transfer emitter output to result
          transfer_emitter_output(result)

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

        # Track consumed individual node indices (not just signatures) so that
        # multiple nodes sharing the same signature are matched 1:1 in order
        # rather than collapsed into a single match.
        # This is especially important for TOML [[array_of_tables]] which can
        # legitimately repeat headers.
        consumed_template_indices = ::Set.new
        sig_cursor = Hash.new(0)
        prev_emitted_end_line = nil
        prev_emitted_analysis = nil

        # Pre-compute position-aware trailing groups for template-only nodes.
        dest_sigs = ::Set.new
        dest_nodes.each { |n|
          sig = dest_analysis.generate_signature(n)
          dest_sigs << sig if sig
        }
        refined_template_ids = ::Set.new(refined_matches.keys.map(&:object_id))

        trailing_groups, all_matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: template_nodes,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { template_analysis.generate_signature(node) },
          refined_template_ids: refined_template_ids,
          add_template_only_nodes: @add_template_only_nodes,
        )

        # Emit template-only nodes that precede the first matched template node
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          emit_gap_before_node(info[:node], template_analysis, prev_emitted_end_line, prev_emitted_analysis)
          emit_node(info[:node], template_analysis)
          prev_emitted_end_line = emitted_end_line_for(info[:node])
          prev_emitted_analysis = template_analysis
        end

        # First pass: Process destination nodes
        dest_nodes.each do |dest_node|
          dest_sig = dest_analysis.generate_signature(dest_node)

          # Check for signature match
          if dest_sig && template_by_sig[dest_sig]
            # Find the next unconsumed template node with this signature
            candidates = template_by_sig[dest_sig]
            cursor = sig_cursor[dest_sig]
            template_info = nil

            while cursor < candidates.size
              candidate = candidates[cursor]
              unless consumed_template_indices.include?(candidate[:index])
                template_info = candidate
                break
              end
              cursor += 1
            end

            if template_info
              template_node = template_info[:node]
              selected_node, selected_analysis = preferred_node_with_analysis(
                template_node,
                dest_node,
                template_analysis,
                dest_analysis,
              )

              emit_gap_before_node(
                selected_node,
                selected_analysis,
                prev_emitted_end_line,
                prev_emitted_analysis,
                skip_for_borrowed_leading_region: @preference == :template && leading_region_present?(dest_node, dest_analysis),
              )

              # Both have this node - merge them
              merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
              prev_emitted_end_line = emitted_end_line_for(selected_node)
              prev_emitted_analysis = selected_analysis

              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1
            elsif @remove_template_missing_nodes
              # All template copies consumed — treat the extra destination copy as destination-only.
              emit_removed_destination_node_comments(dest_node, dest_analysis)
            else
              emit_gap_before_node(dest_node, dest_analysis, prev_emitted_end_line, prev_emitted_analysis)
              emit_node(dest_node, dest_analysis)
              prev_emitted_end_line = emitted_end_line_for(dest_node)
              prev_emitted_analysis = dest_analysis
            end
          elsif refined_dest_to_template.key?(dest_node)
            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = template_analysis.generate_signature(template_node)
            selected_node, selected_analysis = preferred_node_with_analysis(
              template_node,
              dest_node,
              template_analysis,
              dest_analysis,
            )

            # Find and consume the matching template index
            if template_sig && template_by_sig[template_sig]
              template_by_sig[template_sig].each do |info|
                unless consumed_template_indices.include?(info[:index])
                  consumed_template_indices << info[:index]
                  break
                end
              end
            end

            # Merge matched nodes
            emit_gap_before_node(
              selected_node,
              selected_analysis,
              prev_emitted_end_line,
              prev_emitted_analysis,
              skip_for_borrowed_leading_region: @preference == :template && leading_region_present?(dest_node, dest_analysis),
            )
            merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
            prev_emitted_end_line = emitted_end_line_for(selected_node)
            prev_emitted_analysis = selected_analysis
          elsif @remove_template_missing_nodes
            # Destination-only node
            emit_removed_destination_node_comments(dest_node, dest_analysis)
          else
            emit_gap_before_node(dest_node, dest_analysis, prev_emitted_end_line, prev_emitted_analysis)
            emit_node(dest_node, dest_analysis)
            prev_emitted_end_line = emitted_end_line_for(dest_node)
            prev_emitted_analysis = dest_analysis
          end

          # Flush interior trailing groups
          flush_ready_trailing_groups(
            trailing_groups: trailing_groups,
            matched_indices: all_matched_indices,
            consumed_indices: consumed_template_indices,
          ) do |info|
            emit_gap_before_node(info[:node], template_analysis, prev_emitted_end_line, prev_emitted_analysis)
            emit_node(info[:node], template_analysis)
            prev_emitted_end_line = emitted_end_line_for(info[:node])
            prev_emitted_analysis = template_analysis
          end
        end

        # Emit remaining trailing groups (tail + safety net)
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices,
        ) do |info|
          emit_gap_before_node(info[:node], template_analysis, prev_emitted_end_line, prev_emitted_analysis)
          emit_node(info[:node], template_analysis)
          prev_emitted_end_line = emitted_end_line_for(info[:node])
          prev_emitted_analysis = template_analysis
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
          selected_node, selected_analysis = preferred_node_with_analysis(
            template_node,
            dest_node,
            template_analysis,
            dest_analysis,
          )

          comment_source_node, comment_source_analysis = if @preference == :template
            [dest_node, dest_analysis]
          else
            [nil, selected_analysis]
          end

          emit_leading_region(
            selected_node,
            selected_analysis,
            comment_source_node: comment_source_node,
            comment_analysis: comment_source_analysis,
          )

          # Emit table header and merge children
          @emitter.emit_table_header(
            selected_node.table_name || dest_node.table_name || template_node.table_name,
            inline_comment: preferred_inline_comment_text(
              selected_node,
              selected_analysis,
              comment_source_node: comment_source_node,
              comment_analysis: comment_source_analysis,
            ),
          )

          template_children = template_node.mergeable_children
          dest_children = dest_node.mergeable_children

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
          emit_node(
            template_node,
            template_analysis,
            comment_source_node: dest_node,
            comment_analysis: dest_analysis,
          )
        end
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        emit_leading_region(
          node,
          analysis,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
        )

        # Emit the node content
        start_line = node.start_line
        end_line = emitted_end_line_for(node)

        if start_line && end_line
          lines = []
          (start_line..end_line).each do |line_num|
            line = analysis.line_at(line_num)
            lines << line if line
          end
          emit_node_lines(
            lines,
            node,
            analysis,
            comment_source_node: comment_source_node,
            comment_analysis: comment_analysis,
          )
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

      def transfer_emitter_output(result)
        emitted_content = @emitter.to_s
        return if emitted_content.empty?

        emitted_content.lines.each do |line|
          result.add_line(line.chomp, decision: MergeResult::DECISION_MERGED, source: :merged)
        end
      end

      def emit_removed_destination_node_comments(node, analysis)
        if table_like_node?(node)
          emit_leading_region(node, analysis)
          emit_removed_destination_node_inline_comments(node, analysis)
          node.mergeable_children.each do |child|
            emit_removed_destination_node_comments(child, analysis)
          end
        else
          emit_leading_region(node, analysis)
          emit_removed_destination_node_inline_comments(node, analysis)
        end
      end

      def emit_removed_destination_node_inline_comments(node, analysis)
        inline_region = attachment_region(node, analysis, :inline_region)
        return unless inline_region && !inline_region.empty?

        indent = analysis.line_at(node.start_line).to_s[/\A\s*/].to_s.length
        tracked_hashes = Array(inline_region.metadata[:tracked_hashes])

        if tracked_hashes.any?
          tracked_hashes.each do |comment|
            @emitter.emit_tracked_comment(comment.merge(indent: indent, full_line: true))
          end
        else
          @emitter.emit_comment(inline_region.text.to_s.sub(/\A\s*#\s?/, ""))
        end
      end

      def preferred_boundary_analysis(template_analysis, dest_analysis)
        (@preference == :template) ? template_analysis : dest_analysis
      end

      def preferred_comment_only_analysis(template_analysis, dest_analysis)
        preferred = preferred_boundary_analysis(template_analysis, dest_analysis)
        alternate = preferred.equal?(template_analysis) ? dest_analysis : template_analysis

        [preferred, alternate].find do |analysis|
          analysis.statements.empty? && analysis.comment_nodes.any?
        end
      end

      def emit_comment_only_document(analysis)
        return unless analysis

        @emitter.emit_raw_lines(analysis.lines)
      end

      def emit_root_boundary_region(analysis, kind)
        return unless analysis

        augmenter = analysis.comment_augmenter(owners: analysis.statements)
        region = (kind == :preamble) ? augmenter.preamble_region : augmenter.postlude_region
        return unless region

        boundary_lines = root_boundary_lines_for(region, analysis, kind)
        @emitter.emit_raw_lines(boundary_lines) if boundary_lines.any?
      end

      def emit_leading_region(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        region, source_analysis, source_node = preferred_region_with_source(
          node,
          analysis,
          :leading_region,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
        )
        return unless region

        emit_preceding_blank_lines(region, source_analysis)
        @emitter.emit_comment_region(region, source_lines: source_analysis&.lines)
        emit_interstitial_blank_lines((region.end_line || source_node&.start_line).to_i + 1, source_node&.start_line.to_i - 1, source_analysis)
      end

      def root_boundary_lines_for(region, analysis, kind)
        return [] unless region.respond_to?(:nodes)
        return [] if region.nodes.empty?

        last_comment_line = region.nodes.last.line_number
        start_line = if kind == :preamble
          1
        else
          last_structural_root_line_for(analysis) + 1
        end

        return [] if start_line > last_comment_line

        (start_line..last_comment_line).filter_map { |line_num| analysis.line_at(line_num) }
      end

      def preferred_node_with_analysis(template_node, dest_node, template_analysis, dest_analysis)
        if @preference == :template
          [template_node, template_analysis]
        else
          [dest_node, dest_analysis]
        end
      end

      def inline_comment_text_for(node)
        inline_comment = node.respond_to?(:inline_comment) ? node.inline_comment : nil
        return unless inline_comment

        inline_comment[:text]
      end

      def preferred_inline_comment_text(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        region, = preferred_region_with_source(
          node,
          analysis,
          :inline_region,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
        )
        return unless region && !region.empty?

        tracked = Array(region.metadata[:tracked_hashes]).first
        return tracked[:text] if tracked && tracked[:text]

        inline_comment_text_for(node)
      end

      def emit_node_lines(lines, node, analysis, comment_source_node: nil, comment_analysis: analysis)
        return if lines.empty?

        inline_region, = preferred_region_with_source(
          node,
          analysis,
          :inline_region,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
        )

        unless inline_region && !inline_region.empty?
          @emitter.emit_raw_lines(lines)
          return
        end

        existing_inline_region = attachment_region(node, analysis, :inline_region)
        first_line = strip_inline_region_from_line(lines.first, existing_inline_region)

        @emitter.emit_raw_lines([first_line])
        @emitter.emit_comment_region(inline_region, inline: true, source_lines: comment_analysis&.lines)
        @emitter.emit_raw_lines(lines.drop(1)) if lines.length > 1
      end

      def preferred_region_with_source(node, analysis, region_kind, comment_source_node: nil, comment_analysis: analysis)
        primary_region = attachment_region(node, analysis, region_kind)
        return [primary_region, analysis, node] if primary_region && !primary_region.empty?

        if comment_source_node && comment_analysis
          source_region = attachment_region(comment_source_node, comment_analysis, region_kind)
          return [source_region, comment_analysis, comment_source_node] if source_region && !source_region.empty?
        end

        [primary_region, analysis, node]
      end

      def attachment_region(node, analysis, region_kind)
        return unless node && analysis

        attachment = analysis.comment_attachment_for(node)
        attachment.public_send(region_kind) if attachment.respond_to?(region_kind)
      end

      def strip_inline_region_from_line(line, inline_region)
        return line unless line
        return line unless inline_region && !inline_region.empty?

        tracked = Array(inline_region.metadata[:tracked_hashes]).first
        column = tracked && tracked[:column]
        return line unless column

        line.byteslice(0...column).to_s.rstrip
      end


      def emit_interstitial_blank_lines(start_line, end_line, analysis)
        return unless analysis
        return unless start_line && end_line && start_line <= end_line

        lines = []
        (start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line && line.strip.empty?
        end
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def emit_gap_before_node(node, analysis, prev_end_line, prev_analysis, skip_for_borrowed_leading_region: false)
        return unless node && analysis && prev_end_line
        return unless prev_analysis&.equal?(analysis)
        return unless node.respond_to?(:start_line) && node.start_line
        return if skip_for_borrowed_leading_region

        leading_region = attachment_region(node, analysis, :leading_region)
        return if leading_region && (!leading_region.respond_to?(:empty?) || !leading_region.empty?)

        emit_interstitial_blank_lines(prev_end_line + 1, node.start_line - 1, analysis)
      end

      def leading_region_present?(node, analysis)
        region = attachment_region(node, analysis, :leading_region)
        region && (!region.respond_to?(:empty?) || !region.empty?)
      end

      def emit_preceding_blank_lines(region, analysis)
        return unless analysis
        return unless region.respond_to?(:start_line) && region.start_line

        line_num = region.start_line - 1
        lines = []

        while line_num >= 1
          line = analysis.line_at(line_num)
          break unless line && line.strip.empty?

          lines.unshift(line)
          line_num -= 1
        end

        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def emitted_end_line_for(node)
        return node.start_line if table_like_without_children?(node)

        if table_like_node?(node)
          child_end_line = node.mergeable_children.map(&:end_line).compact.max
          return child_end_line if child_end_line
        end

        node.end_line
      end

      def last_structural_root_line_for(analysis)
        analysis.statements.map { |node| emitted_end_line_for(node) }.compact.max || 0
      end

      def table_like_without_children?(node)
        table_like_node?(node) && node.mergeable_children.empty?
      end

      def table_like_node?(node)
        node.table? || (node.respond_to?(:array_of_tables?) && node.array_of_tables?)
      end
    end
  end
end
