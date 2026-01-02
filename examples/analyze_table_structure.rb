#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to analyze structural differences between tree-sitter and Citrus backends
# specifically for table nodes and their content.
#
# Goal: Understand how to NORMALIZE the ASTs so merge logic works identically
# across backends.
#
# Run from toml-merge directory:
#   bundle exec ruby examples/analyze_table_structure.rb

require "bundler/setup"
require "toml/merge"

# Simple TOML with a table containing key-value pairs
SIMPLE_TABLE_TOML = <<~TOML
  # Root comment
  root_key = "root_value"

  [server]
  host = "localhost"
  port = 8080

  [database]
  name = "mydb"
TOML

def print_node_tree(node, indent = 0, max_depth = 10)
  return if indent > max_depth
  return unless node

  prefix = "  " * indent
  type = node.respond_to?(:type) ? node.type : node.class.name.split("::").last

  # Get position info
  start_line = node.respond_to?(:start_point) ? node.start_point&.row : nil
  end_line = node.respond_to?(:end_point) ? node.end_point&.row : nil

  # Get text preview
  text = if node.respond_to?(:text)
    node.text.to_s.gsub("\n", "\\n")[0..40]
  elsif node.respond_to?(:string)
    node.string.to_s.gsub("\n", "\\n")[0..40]
  else
    ""
  end

  puts "#{prefix}#{type} (lines #{start_line}-#{end_line}): #{text.inspect}"

  # Recurse into children
  if node.respond_to?(:children) && node.children.any?
    node.children.each { |child| print_node_tree(child, indent + 1, max_depth) }
  elsif node.respond_to?(:each)
    node.each { |child| print_node_tree(child, indent + 1, max_depth) }
  end
end

def analyze_table_structure(analysis, label)
  puts "\n" + "=" * 80
  puts label
  puts "=" * 80

  puts "\nBackend: #{analysis.backend}"
  puts "Valid: #{analysis.valid?}"

  unless analysis.valid?
    puts "Errors: #{analysis.errors.inspect}"
    return
  end

  root = analysis.root_node
  puts "\n--- Full AST Tree ---"
  print_node_tree(root.node, 0, 6)

  puts "\n--- Tables via FileAnalysis#tables ---"
  analysis.tables.each_with_index do |table, idx|
    puts "\nTable #{idx + 1}:"
    puts "  type: #{table.type}"
    puts "  canonical_type: #{table.canonical_type}"
    puts "  table_name: #{table.table_name.inspect}"
    puts "  start_line: #{table.start_line}"
    puts "  end_line: #{table.end_line}"
    puts "  content: #{table.content.inspect}"

    puts "  pairs (via #pairs method):"
    table.pairs.each do |pair|
      puts "    - #{pair.type}: #{pair.key_name} (lines #{pair.start_line}-#{pair.end_line})"
    end

    puts "  children (via #children method):"
    table.children.each do |child|
      child_type = child.respond_to?(:type) ? child.type : child.class.name
      puts "    - #{child_type}"
    end
  end

  puts "\n--- Root Pairs via FileAnalysis#root_pairs ---"
  analysis.root_pairs.each do |pair|
    puts "  - #{pair.type}: #{pair.key_name} = ... (lines #{pair.start_line}-#{pair.end_line})"
  end

  puts "\n--- All Statements ---"
  analysis.statements.each_with_index do |stmt, idx|
    type = stmt.respond_to?(:type) ? stmt.type : stmt.class.name.split("::").last
    canonical = stmt.respond_to?(:canonical_type) ? stmt.canonical_type : "N/A"
    start_l = stmt.respond_to?(:start_line) ? stmt.start_line : "?"
    end_l = stmt.respond_to?(:end_line) ? stmt.end_line : "?"
    puts "  #{idx}: #{type} (canonical: #{canonical}) lines #{start_l}-#{end_l}"
  end
end

puts "=" * 80
puts "Table Structure Analysis - Tree-Sitter vs Citrus"
puts "=" * 80
puts "\nGoal: Understand structural differences to normalize ASTs for merge logic"
puts "\nTOML being analyzed:"
puts SIMPLE_TABLE_TOML
puts "-" * 80

# Analyze with default backend (tree-sitter if available)
begin
  analysis = Toml::Merge::FileAnalysis.new(SIMPLE_TABLE_TOML)
  analyze_table_structure(analysis, "Analysis with Auto-Selected Backend")
rescue => e
  puts "Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Force Citrus backend if available
begin
  require "tree_haver"

  if TreeHaver::Backends::Citrus.available?
    puts "\n\n"
    # Use TreeHaver.with_backend to force Citrus
    TreeHaver.with_backend(:citrus) do
      analysis = Toml::Merge::FileAnalysis.new(SIMPLE_TABLE_TOML)
      analyze_table_structure(analysis, "Analysis with Citrus Backend (forced via TreeHaver.with_backend)")
    end
  else
    puts "\nCitrus backend not available for comparison"
  end
rescue => e
  puts "Error with Citrus: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Analysis Summary
puts "\n" + "=" * 80
puts "STRUCTURAL ANALYSIS SUMMARY"
puts "=" * 80

puts <<~SUMMARY

  KEY QUESTIONS TO ANSWER:

  1. For tree-sitter:
     - Does the `table` node include pairs as children?
     - What is the start_line and end_line of a table node?
     - Does table.content include the key-value pairs?

  2. For Citrus:
     - Does the `table` node include pairs as children?
     - What is the start_line and end_line of a table node?
     - Does table.content include the key-value pairs?

  3. Where are the pairs located in each AST?
     - As children of the table node?
     - As siblings of the table node in the document?

  NORMALIZATION OPTIONS:

  A. Normalize at TreeHaver level:
     - Modify tree_haver's Citrus adapter to restructure the AST
     - Make Citrus table nodes include their pairs as children
     - This is the "correct" fix but requires tree_haver changes

  B. Normalize at NodeWrapper level:
     - Make NodeWrapper#content smart enough to find associated pairs
     - For Citrus tables, scan sibling nodes until next table
     - This is a workaround but contained within toml-merge

  C. Normalize at FileAnalysis level:
     - Post-process the AST to restructure nodes
     - Combine table headers with their content
     - Similar to option B but at a different layer

SUMMARY

puts "=" * 80
puts "Script complete!"
puts "=" * 80
