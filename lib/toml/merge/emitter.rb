# frozen_string_literal: true

module Toml
  module Merge
    # Custom TOML emitter that preserves comments and formatting.
    # This class provides utilities for emitting TOML while maintaining
    # the original structure, comments, and style choices.
    #
    # Inherits common emitter functionality from Ast::Merge::EmitterBase.
    #
    # @example Basic usage
    #   emitter = Emitter.new
    #   emitter.emit_table_header("section")
    #   emitter.emit_key_value("key", "value")
    class Emitter < Ast::Merge::EmitterBase
      # Initialize subclass-specific state
      def initialize_subclass_state(**options)
        # TOML doesn't need separator tracking like JSON
      end

      # Clear subclass-specific state
      def clear_subclass_state
        # Nothing to clear for TOML
      end

      # Emit a tracked comment from CommentTracker
      # @param comment [Hash] Comment with :text, :indent
      def emit_tracked_comment(comment)
        indent = " " * (comment[:indent] || 0)
        @lines << "#{indent}# #{comment[:text]}"
      end

      # Emit a comment line
      #
      # @param text [String] Comment text (without #)
      # @param inline [Boolean] Whether this is an inline comment
      def emit_comment(text, inline: false)
        if inline
          # Inline comments are appended to the last line
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          @lines << "#{current_indent}# #{text}"
        end
      end

      # Emit a table header
      #
      # @param name [String] Table name (e.g., "package" or "dependencies.dev")
      def emit_table_header(name)
        @lines << "[#{name}]"
      end

      # Emit an array of tables header
      #
      # @param name [String] Array of tables name
      def emit_array_of_tables_header(name)
        @lines << "[[#{name}]]"
      end

      # Emit a key-value pair
      #
      # @param key [String] Key name
      # @param value [String] Value (already formatted as TOML)
      # @param inline_comment [String, nil] Optional inline comment
      def emit_key_value(key, value, inline_comment: nil)
        line = "#{current_indent}#{key} = #{value}"
        line += " # #{inline_comment}" if inline_comment
        @lines << line
      end

      # Emit an inline table
      #
      # @param key [String] Key name
      # @param pairs [Hash] Key-value pairs for the inline table
      def emit_inline_table(key, pairs)
        formatted_pairs = pairs.map { |k, v| "#{k} = #{v}" }.join(", ")
        @lines << "#{current_indent}#{key} = { #{formatted_pairs} }"
      end

      # Emit an inline array
      #
      # @param key [String] Key name
      # @param items [Array] Array items (already formatted)
      def emit_inline_array(key, items)
        formatted_items = items.join(", ")
        @lines << "#{current_indent}#{key} = [#{formatted_items}]"
      end

      # Emit a multi-line array start
      #
      # @param key [String] Key name
      def emit_array_start(key)
        @lines << "#{current_indent}#{key} = ["
        indent
      end

      # Emit an array item
      #
      # @param value [String] Item value (already formatted)
      def emit_array_item(value)
        @lines << "#{current_indent}#{value},"
      end

      # Emit an array end
      def emit_array_end
        dedent
        @lines << "#{current_indent}]"
      end

      # Get the output as a TOML string
      #
      # @return [String]
      def to_toml
        to_s
      end
    end
  end
end
