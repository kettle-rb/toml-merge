# frozen_string_literal: true

# External gems
# TreeHaver provides a unified cross-Ruby interface to tree-sitter and Citrus
require "tree_haver"

# Register tree-sitter grammar (preferred, fast)
tree_sitter_finder = TreeHaver::GrammarFinder.new(:toml)
tree_sitter_available = tree_sitter_finder.available?
tree_sitter_finder.register! if tree_sitter_available

# Register Citrus grammar (fallback, pure Ruby)
citrus_finder = TreeHaver::CitrusGrammarFinder.new(
  language: :toml,
  gem_name: "toml-rb",
  grammar_const: "TomlRB::Document",
  require_path: "toml-rb"  # Explicit require path (gem uses "toml-rb.rb" not "toml/rb.rb")
)
citrus_available = citrus_finder.available?
citrus_finder.register! if citrus_available

# Ensure at least one grammar is available
unless tree_sitter_available || citrus_available
  raise TreeHaver::NotAvailable,
    "No TOML parser available. Install either:\n" \
    "  - tree-sitter-toml (fast): #{tree_sitter_finder.not_found_message}\n" \
    "  - toml-rb gem (pure Ruby): #{citrus_finder.not_found_message}"
end

# Warn if Citrus backend is forced but toml-rb not available
if TreeHaver.backend == :citrus && !citrus_available && tree_sitter_available
  warn "WARNING: TREE_HAVER_BACKEND=citrus but toml-rb not installed. " \
    "Using tree-sitter backend instead. Install toml-rb: gem install toml-rb"
  TreeHaver.backend = :auto
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
    autoload :NodeWrapper, "toml/merge/node_wrapper"
    autoload :ConflictResolver, "toml/merge/conflict_resolver"
    autoload :SmartMerger, "toml/merge/smart_merger"
    autoload :TableMatchRefiner, "toml/merge/table_match_refiner"
  end
end

Toml::Merge::Version.class_eval do
  extend VersionGem::Basic
end
