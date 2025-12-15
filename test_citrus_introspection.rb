#!/usr/bin/env ruby
# Investigate Citrus grammar structure to find dynamic solution

require "bundler/setup"
require "toml-rb"
require "citrus"

puts "=== Citrus Grammar Introspection ==="

# Get the grammar
grammar = TomlRB::Document

puts "\nGrammar class: #{grammar.class}"
puts "Grammar name: #{grammar.name}"
puts "Grammar ancestors: #{grammar.ancestors.first(5).join(", ")}"

puts "\n=== Rules ==="
if grammar.respond_to?(:rules)
  puts "Has rules method: true"
  rules = grammar.rules
  puts "Rules class: #{rules.class}"
  puts "Number of rules: #{rules.size}"

  # Show first few rules
  rules.first(10).each do |name, rule|
    puts "\n#{name}:"
    puts "  Class: #{rule.class}"
    puts "  Terminal?: #{rule.respond_to?(:terminal?) ? rule.terminal? : 'N/A'}"
    puts "  Methods: #{(rule.methods - Object.methods).grep(/rule|name|terminal/).join(", ")}"
  end
end

puts "\n=== Rule Names ==="
if grammar.respond_to?(:rule_names)
  names = grammar.rule_names
  puts "Rule names: #{names.first(20).join(", ")}"
end

puts "\n=== Checking Individual Rules ==="
if grammar.respond_to?(:rules)
  rules = grammar.rules

  # Check a structural rule (table)
  if rules.key?(:table)
    puts "\nTable rule:"
    table_rule = rules[:table]
    puts "  Class: #{table_rule.class}"
    puts "  String: #{table_rule.to_s[0..100]}"
    puts "  Terminal: #{table_rule.terminal? rescue 'N/A'}"
  end

  # Check a terminal rule (if exists)
  if rules.key?(:"[")
    puts "\n'[' rule:"
    bracket_rule = rules[:"["]
    puts "  Class: #{bracket_rule.class}"
    puts "  String: #{bracket_rule.to_s[0..100]}"
    puts "  Terminal: #{bracket_rule.terminal? rescue 'N/A'}"
  end
end

puts "\n=== Parsing and Checking Match Info ==="
source = "[test]\nkey = 'value'"
match = grammar.parse(source)

puts "\nRoot match:"
puts "  Grammar: #{match.grammar.name rescue 'N/A'}"
puts "  Events first: #{match.events.first}"
puts "  Events first class: #{match.events.first.class}"

# Check if we can determine rule type from the event object
first_event = match.events.first
if first_event.respond_to?(:rules)
  puts "  First event has rules: #{first_event.rules.inspect}"
end
if first_event.respond_to?(:rule)
  puts "  First event rule: #{first_event.rule.inspect}"
end
if first_event.respond_to?(:name)
  puts "  First event name: #{first_event.name.inspect}"
end

# Check available methods on the event
event_methods = (first_event.methods - Object.methods).sort
puts "  First event methods: #{event_methods.grep(/rule|name|terminal|type/).join(", ")}"

puts "\n=== Checking Child Matches ==="
if match.matches.any?
  first_child = match.matches.first
  puts "First child:"
  puts "  Events first: #{first_child.events.first}"
  puts "  Events first class: #{first_child.events.first.class}"

  child_event = first_child.events.first
  if child_event.is_a?(Symbol)
    puts "  ✓ Child event is a Symbol: #{child_event}"
    puts "  Can look up in grammar.rules: #{grammar.rules.key?(child_event)}"
  end
end

