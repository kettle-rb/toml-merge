#!/usr/bin/env ruby
# Test to see what Citrus::Match provides

require "bundler/setup"
require "toml-rb"

source = "[section]\nkey = 'value'"
match = TomlRB::Document.parse(source)

puts "=== Citrus::Match Structure ==="
puts "Class: #{match.class}"
puts "Methods: #{match.methods.grep(/event|name|rule/).sort.join(", ")}"

puts "\n=== Events ==="
puts "events: #{match.events.inspect}"
puts "events.class: #{match.events.class}"

if match.events.any?
  puts "\nFirst event: #{match.events.first.inspect}"
  puts "First event class: #{match.events.first.class}"
end

puts "\n=== Grammar Name ==="
puts "grammar.name: #{match.grammar.name}" if match.respond_to?(:grammar)

puts "\n=== Traversing Tree ==="
def show_node(node, indent = 0)
  prefix = "  " * indent
  events = node.respond_to?(:events) ? node.events : []
  name = events.first if events.any?
  text = node.string[0..30].inspect

  puts "#{prefix}#{name || 'unknown'}: #{text}"

  if node.respond_to?(:matches) && node.matches.any?
    node.matches.each { |child| show_node(child, indent + 1) }
  end
end

show_node(match)

