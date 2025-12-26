# frozen_string_literal: true

# External gems
# TreeHaver provides a unified cross-Ruby interface to tree-sitter
require "tree_haver"

# Register tree-sitter toml grammar
toml_finder = TreeHaver::GrammarFinder.new(:toml)
toml_available = toml_finder.available?
toml_finder.register! if toml_available

# Ensure grammar is available
unless toml_available
  warn "WARNING: TOML grammar not available. #{toml_finder.not_found_message}"
end

require "version_gem"
require "set"

# Shared merge infrastructure
require "ast/merge"

# This gem
require_relative "merge/version"

# Toml::Merge provides a TOML file smart merge system using tree-sitter AST analysis.
# It intelligently merges template and destination TOML files by identifying matching
# keys and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.toml")
#   destination = File.read("destination.toml")
#   merger = Toml::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Toml::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Toml
  # Smart merge system for TOML files using tree-sitter AST analysis.
  # Provides intelligent merging by understanding TOML structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes TOML structure
  # @see ConflictResolver Resolves content conflicts
  module Merge
    # Base error class for Toml::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a TOML file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(toml_content)
    #   rescue ParseError => e
    #     puts "TOML syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The TOML source that failed to parse
      # @param errors [Array] Parse errors from tree-sitter
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    autoload :DebugLogger, "toml/merge/debug_logger"
    autoload :FileAnalysis, "toml/merge/file_analysis"
    autoload :MergeResult, "toml/merge/merge_result"
    autoload :NodeTypeNormalizer, "toml/merge/node_type_normalizer"
    autoload :NodeWrapper, "toml/merge/node_wrapper"
    autoload :ConflictResolver, "toml/merge/conflict_resolver"
    autoload :SmartMerger, "toml/merge/smart_merger"
    autoload :TableMatchRefiner, "toml/merge/table_match_refiner"
  end
end

Toml::Merge::Version.class_eval do
  extend VersionGem::Basic
end
