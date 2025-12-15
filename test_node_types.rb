#!/usr/bin/env ruby
# Test improved node type extraction

$LOAD_PATH.unshift File.expand_path("../tree_haver/lib", __dir__)

require "bundler/setup"
require "tree_haver"
require "toml-rb"  # Load toml-rb gem to get TomlRB::Document

# Register Citrus grammar
TreeHaver.register_language(:toml, grammar_module: TomlRB::Document)

# Force Citrus backend
TreeHaver.backend = :citrus

# Parse TOML
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse("[section]\nkey = 'value'\n\n[another]\nfoo = 123")

puts "=== Root Node ==="
root = tree.root_node
puts "Type: #{root.type}"
puts "Children: #{root.child_count}"

puts "\n=== Child Nodes ==="
root.children.each_with_index do |child, i|
  puts "Child #{i}:"
  puts "  Type: #{child.type}"
  puts "  Text: #{child.text[0..40].inspect}"
  puts "  Start: #{child.start_byte}, End: #{child.end_byte}"

  if child.child_count > 0
    puts "  Subchildren:"
    child.children.first(3).each do |subchild|
      puts "    - #{subchild.type}: #{subchild.text[0..20].inspect}"
    end
  end
end

puts "\n=== Test Complete ==="

