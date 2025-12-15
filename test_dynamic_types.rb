#!/usr/bin/env ruby
# Test dynamic node type extraction with Citrus

$LOAD_PATH.unshift File.expand_path("../tree_haver/lib", __dir__)

require "bundler/setup"
require "tree_haver"
require "toml-rb"

# Register and use Citrus backend
TreeHaver.register_language(:toml, grammar_module: TomlRB::Document)
TreeHaver.backend = :citrus

# Parse TOML
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse(<<~TOML)
  # This is a comment
  [section]
  key = 'value'
  number = 123
  
  [[array_table]]
  name = "first"
TOML

puts "=== Dynamic Type Extraction Test ==="
root = tree.root_node
puts "Root type: #{root.type}"
puts "Root structural?: #{root.structural?}"
puts "\nChildren:"

def show_node(node, indent = 0)
  prefix = "  " * indent
  structural = node.structural? ? "📦" : "🔤"
  puts "#{prefix}#{structural} #{node.type}: #{node.text[0..30].inspect}"

  if node.child_count > 0 && node.child_count < 10
    node.children.each { |child| show_node(child, indent + 1) }
  end
end

root.children.each do |child|
  show_node(child)
  puts if child.structural?
end

puts "\n=== Filtering Structural Nodes ==="
structural_nodes = root.children.select(&:structural?)
puts "Found #{structural_nodes.count} structural nodes:"
structural_nodes.each do |node|
  puts "  - #{node.type}: #{node.text[0..40].inspect}"
end

puts "\n=== Test Complete ==="

