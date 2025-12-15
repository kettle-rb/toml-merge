#!/usr/bin/env ruby
# Test TOML-specific helper methods

$LOAD_PATH.unshift File.expand_path("../tree_haver/lib", __dir__)

require "bundler/setup"
require "tree_haver"
require "toml-rb"

# Load and include TOML helpers
require "tree_haver/backends/citrus/toml_helpers"
TreeHaver::Backends::Citrus::Node.include(TreeHaver::Backends::Citrus::TomlHelpers)

# Register and use Citrus backend
TreeHaver.register_language(:toml, grammar_module: TomlRB::Document)
TreeHaver.backend = :citrus

# Parse TOML
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse(<<~TOML)
  [section]
  key = 'value'
  number = 123
  
  [[array_table]]
  name = "first"
TOML

puts "=== Testing Helper Methods ==="
root = tree.root_node

root.children.each do |child|
  next if child.whitespace?  # Skip whitespace

  puts "\n--- Node ---"
  puts "Type: #{child.type}"
  puts "Text: #{child.text[0..40].inspect}"

  if child.table?
    puts "✓ Is table: #{child.key_name}"
  elsif child.table_array?
    puts "✓ Is table array: #{child.key_name}"
  elsif child.pair?
    puts "✓ Is key-value pair"
    puts "  Key: #{child.key_name}"
    if child.value_node
      puts "  Value type: #{child.value_node.type}"
      puts "  Value text: #{child.value_node.text.inspect}"
    end
  elsif child.comment?
    puts "✓ Is comment"
  end
end

puts "\n=== Helper Methods Working! ==="

