# frozen_string_literal: true

# Dependency detection helpers for conditional test execution in toml-merge
#
# This module detects which optional TOML parsing backends are available
# and configures RSpec to skip tests that require unavailable dependencies.
#
# Usage in specs:
#   it "requires tree-sitter-toml", :tree_sitter_toml do
#     # This test only runs when tree-sitter-toml is available
#   end
#
#   it "requires toml-rb (Citrus)", :toml_rb do
#     # This test only runs when toml-rb is available
#   end
#
#   it "requires any TOML backend", :toml_backend do
#     # This test only runs when at least one TOML backend is available
#   end

module TomlMergeDependencies
  class << self
    # Check if tree-sitter-toml grammar is available AND working via TreeHaver
    # This checks that parsing actually works, not just that a grammar file exists
    def tree_sitter_toml_available?
      return @tree_sitter_toml_available if defined?(@tree_sitter_toml_available)
      @tree_sitter_toml_available = begin
        # TreeHaver handles grammar discovery and raises NotAvailable if not found
        parser = TreeHaver.parser_for(:toml)
        result = parser.parse("key = \"value\"")
        !result.nil? && result.root_node && !result.root_node.has_error?
      rescue TreeHaver::NotAvailable
        false
      end
    end

    # Check if toml-rb gem is available (Citrus backend)
    def toml_rb_available?
      return @toml_rb_available if defined?(@toml_rb_available)
      @toml_rb_available = begin
        require "toml-rb"
        true
      rescue LoadError
        false
      end
    end

    # Check if at least one TOML backend is available
    def any_toml_backend_available?
      tree_sitter_toml_available? || toml_rb_available?
    end

    # Check if running on JRuby
    def jruby?
      defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
    end

    # Check if running on MRI (CRuby)
    def mri?
      defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
    end

    # Get a summary of available dependencies (for debugging)
    def summary
      {
        tree_sitter_toml: tree_sitter_toml_available?,
        toml_rb: toml_rb_available?,
        any_toml_backend: any_toml_backend_available?,
        ruby_engine: RUBY_ENGINE,
        jruby: jruby?,
        mri: mri?,
      }
    end
  end
end

RSpec.configure do |config|
  # Define exclusion filters for optional dependencies
  # Tests tagged with these will be skipped when the dependency is not available

  config.before(:suite) do
    # Print dependency summary if TOML_MERGE_DEBUG is set
    if ENV["TOML_MERGE_DEBUG"]
      puts "\n=== Toml::Merge Test Dependencies ==="
      TomlMergeDependencies.summary.each do |dep, available|
        status = case available
        when true then "✓ available"
        when false then "✗ not available"
        else available.to_s
        end
        puts "  #{dep}: #{status}"
      end
      puts "======================================\n"
    end
  end

  # ============================================================
  # Positive tags: run when dependency IS available
  # ============================================================

  # Skip tests tagged :tree_sitter_toml when tree-sitter-toml grammar is not available
  config.filter_run_excluding tree_sitter_toml: true unless TomlMergeDependencies.tree_sitter_toml_available?

  # Skip tests tagged :toml_rb when toml-rb gem is not available
  config.filter_run_excluding toml_rb: true unless TomlMergeDependencies.toml_rb_available?

  # Skip tests tagged :toml_backend when no TOML backend is available
  config.filter_run_excluding toml_backend: true unless TomlMergeDependencies.any_toml_backend_available?

  # Skip tests tagged :jruby when not running on JRuby
  config.filter_run_excluding jruby: true unless TomlMergeDependencies.jruby?

  # ============================================================
  # Negated tags: run when dependency is NOT available
  # ============================================================

  # Skip tests tagged :not_tree_sitter_toml when tree-sitter-toml IS available
  config.filter_run_excluding not_tree_sitter_toml: true if TomlMergeDependencies.tree_sitter_toml_available?

  # Skip tests tagged :not_toml_rb when toml-rb IS available
  config.filter_run_excluding not_toml_rb: true if TomlMergeDependencies.toml_rb_available?

  # Skip tests tagged :not_jruby when running on JRuby
  config.filter_run_excluding not_jruby: true if TomlMergeDependencies.jruby?
end

