# frozen_string_literal: true

module Toml
  module Merge
    # Tracks pre-extracted TOML comment entries and exposes shared comment helpers.
    #
    # This keeps wrapper-level comment association and analysis-layer shared
    # comment APIs on one lookup implementation.
    class CommentTracker
      attr_reader :lines, :comment_entries, :backend

      def initialize(lines, comment_entries, backend: :tree_sitter)
        @lines = Array(lines)
        @comment_entries = Array(comment_entries).map { |entry| normalize_entry(entry) }
        @backend = backend
      end

      def comment_nodes
        @comment_nodes ||= @comment_entries.map { |entry| comment_node_for_entry(entry) }
      end

      def comment_node_at(line_num)
        entry = @comment_entries.find { |comment| comment[:line] == line_num }
        return unless entry

        comment_node_for_entry(entry)
      end

      def comment_region_for_range(range, kind:, full_line_only: false)
        entries = @comment_entries.select { |entry| range.cover?(entry[:line]) }
        entries = entries.select { |entry| entry[:full_line] } if full_line_only
        build_comment_region(kind, entries, metadata: {range: range, full_line_only: full_line_only})
      end

      def comment_attachment_for(owner, line_num: nil, **options)
        owner_line = line_num || owner_start_line(owner)
        return Ast::Merge::Comment::Attachment.new(owner: owner, metadata: options) unless owner_line

        leading_region = build_comment_region(:leading, leading_comments_before(owner_line))
        inline_region = build_comment_region(:inline, owner_inline_comment_entries(owner, line_num: owner_line))

        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: leading_region,
          inline_region: inline_region,
          metadata: {
            source: native_comment_backend? ? :toml_native : :toml_source,
            line_num: owner_line,
          }.merge(options),
        )
      end

      def leading_comments_before(line_num)
        candidates = @comment_entries.select do |entry|
          entry[:full_line] && entry[:line] < line_num
        end
        return [] if candidates.empty?

        selected = []
        current_line = line_num - 1

        while current_line >= 1
          comment = candidates.find { |candidate| candidate[:line] == current_line }

          if comment
            selected.unshift(comment)
            current_line -= 1
          elsif line_at(current_line).to_s.strip.empty?
            current_line -= 1
          else
            break
          end
        end

        selected
      end

      def inline_comment_for(owner, line_num: nil)
        owner_inline_comment_entries(owner, line_num: line_num).first
      end

      def owner_inline_comment_entries(owner, line_num: nil)
        start_line = line_num || owner_start_line(owner)
        return [] unless start_line

        end_line = if owner_table_like?(owner)
          start_line
        else
          owner_end_line(owner) || start_line
        end

        @comment_entries.select do |entry|
          !entry[:full_line] && (start_line..end_line).cover?(entry[:line])
        end
      end

      private

      def normalize_entry(entry)
        entry.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value
        end
      end

      def native_comment_backend?
        @backend != :parslet
      end

      def line_at(line_number)
        @lines[line_number - 1]
      end

      def comment_node_for_entry(entry)
        entry[:comment_node] ||= Ast::Merge::Comment::TrackedHashAdapter.node(entry, style: :hash_comment)
      end

      def build_comment_region(kind, entries, metadata: {})
        return if entries.empty?

        nodes = []
        previous_line = nil
        include_blank_lines = kind != :inline

        entries.sort_by { |entry| entry[:line] }.each do |entry|
          if include_blank_lines && previous_line
            ((previous_line + 1)...entry[:line]).each do |line_number|
              if line_at(line_number).to_s.strip.empty?
                nodes << Ast::Merge::Comment::Empty.new(line_number: line_number, text: line_at(line_number).to_s)
              end
            end
          end

          nodes << comment_node_for_entry(entry)
          previous_line = entry[:line]
        end

        Ast::Merge::Comment::Region.new(
          kind: kind,
          nodes: nodes,
          metadata: {
            source: native_comment_backend? ? :toml_native : :toml_source,
            tracked_hashes: entries,
          }.merge(metadata),
        )
      end

      def owner_table_like?(owner)
        actual_owner = owner.respond_to?(:unwrap) ? owner.unwrap : owner
        return true if actual_owner.respond_to?(:table?) && actual_owner.table?
        return true if actual_owner.respond_to?(:array_of_tables?) && actual_owner.array_of_tables?

        NodeTypeNormalizer.table_type?(NodeTypeNormalizer.canonical_type(actual_owner.type, @backend))
      rescue NoMethodError
        false
      end

      def owner_start_line(owner)
        actual_owner = owner.respond_to?(:unwrap) ? owner.unwrap : owner
        return actual_owner.start_line if actual_owner.respond_to?(:start_line)

        node_start_line(actual_owner)
      end

      def owner_end_line(owner)
        actual_owner = owner.respond_to?(:unwrap) ? owner.unwrap : owner
        return actual_owner.end_line if actual_owner.respond_to?(:end_line)

        node_end_line(actual_owner)
      end

      def node_start_line(node)
        extract_point_row(node.respond_to?(:start_point) ? node.start_point : nil)&.+(1)
      end

      def node_end_line(node)
        extract_point_row(node.respond_to?(:end_point) ? node.end_point : nil)&.+(1)
      end

      def extract_point_row(point)
        return point.row if point.respond_to?(:row)
        return point[:row] if point.is_a?(Hash)

        nil
      end
    end
  end
end
