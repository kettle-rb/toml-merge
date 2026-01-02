#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive script to map ALL node types produced by toml-rb/Citrus backend
# and compare them with tree-sitter-toml types.
#
# This script helps identify the ACTUAL type names used by each backend
# so NodeTypeNormalizer can map them correctly to canonical types.
#
# Run from toml-merge directory:
#   bundle exec ruby examples/map_citrus_node_types.rb

require "bundler/setup"
require "toml/merge"

# Comprehensive TOML sample covering ALL TOML features
COMPREHENSIVE_TOML = <<~TOML
  # Top-level comment
  title = "TOML Comprehensive Test"
  version = 1
  enabled = true
  disabled = false
  pi = 3.14159
  negative_int = -42
  hex_value = 0xDEADBEEF
  octal_value = 0o755
  binary_value = 0b11010110
  
  # String types
  basic_string = "Hello, World!"
  literal_string = 'C:\\Users\\name'
  multiline_basic = """
  First line
  Second line
  """
  multiline_literal = '''
  First line
  Second line
  '''
  
  # Date/time types
  date_only = 2025-12-25
  time_only = 14:30:00
  datetime_local = 2025-12-25T14:30:00
  datetime_offset = 2025-12-25T14:30:00+09:00
  datetime_utc = 2025-12-25T14:30:00Z
  
  # Arrays
  simple_array = [1, 2, 3]
  mixed_array = ["a", 1, true]
  nested_array = [[1, 2], [3, 4]]
  empty_array = []
  
  # Inline tables
  inline_table = { key1 = "value1", key2 = 42 }
  nested_inline = { outer = { inner = "deep" } }
  
  # Dotted keys
  dotted.key.example = "dotted value"
  
  # Regular table
  [server]
  host = "localhost"
  port = 8080
  
  [server.nested]
  option = true
  
  # Array of tables
  [[products]]
  name = "Hammer"
  sku = 738594937
  price = 9.99
  
  [[products]]
  name = "Nail"
  sku = 284758393
  price = 0.05
  
  [[products.variants]]
  size = "small"
  
  [[products.variants]]
  size = "large"
  
  # Another table after array of tables
  [metadata]
  created = 2025-01-01
TOML

def collect_node_types(node, types_hash, depth = 0)
  return unless node

  # Get the type
  type = if node.respond_to?(:type)
    node.type.to_sym
  else
    node.class.name.split("::").last.to_sym
  end

  # Store type with example info
  types_hash[type] ||= {
    count: 0,
    examples: [],
    depths: [],
    has_children: false,
    child_types: Set.new,
  }

  types_hash[type][:count] += 1
  types_hash[type][:depths] << depth

  # Get example text (truncated)
  example = if node.respond_to?(:text)
    node.text.to_s[0..50]
  elsif node.respond_to?(:string)
    node.string.to_s[0..50]
  elsif node.respond_to?(:slice)
    node.slice.to_s[0..50]
  else
    node.to_s[0..50]
  end

  if types_hash[type][:examples].size < 3
    types_hash[type][:examples] << example.gsub("\n", "\\n")
  end

  # Check for children
  if node.respond_to?(:children) && node.children.any?
    types_hash[type][:has_children] = true
    node.children.each do |child|
      child_type = if child.respond_to?(:type)
        child.type.to_sym
      else
        child.class.name.split("::").last.to_sym
      end
      types_hash[type][:child_types] << child_type
      collect_node_types(child, types_hash, depth + 1)
    end
  elsif node.respond_to?(:each)
    types_hash[type][:has_children] = true
    node.each do |child|
      child_type = if child.respond_to?(:type)
        child.type.to_sym
      else
        child.class.name.split("::").last.to_sym
      end
      types_hash[type][:child_types] << child_type
      collect_node_types(child, types_hash, depth + 1)
    end
  end
end

def print_types_report(title, types_hash)
  puts "\n#{"=" * 80}"
  puts title
  puts "=" * 80

  sorted = types_hash.sort_by { |type, info| [-info[:count], type.to_s] }

  sorted.each do |type, info|
    puts "\n  #{type}"
    puts "    Count: #{info[:count]}"
    puts "    Depths: #{info[:depths].uniq.sort.join(", ")}"
    puts "    Has children: #{info[:has_children]}"
    puts "    Child types: #{info[:child_types].to_a.sort.join(", ")}" if info[:child_types].any?
    puts "    Examples:"
    info[:examples].each do |ex|
      puts "      - #{ex.inspect}"
    end
  end
end

puts "=" * 80
puts "TOML Node Type Mapping - Citrus vs Tree-Sitter"
puts "=" * 80
puts "\nThis script identifies the actual node types produced by each backend"
puts "to ensure NodeTypeNormalizer maps them correctly.\n"

# ============================================================
# Part 1: Analyze with TreeHaver (auto-selects backend)
# ============================================================

puts "\n" + "-" * 80
puts "Part 1: TreeHaver Auto-Selected Backend Analysis"
puts "-" * 80

begin
  analysis = Toml::Merge::FileAnalysis.new(COMPREHENSIVE_TOML)

  if analysis.valid?
    puts "\nParse successful!"
    puts "Backend used: #{analysis.respond_to?(:backend) ? analysis.backend : "unknown"}"

    tree_haver_types = {}

    # Collect from root
    root = analysis.root_node
    if root
      puts "Root node type: #{root.type}"
      collect_node_types(root, tree_haver_types)
    end

    # Also check tables and pairs directly
    puts "\nTables found: #{analysis.tables.size}"
    analysis.tables.each do |table|
      puts "  - #{table.type}: #{(table.table_name || table.respond_to?(:array_of_tables?) && table.array_of_tables?) ? "[[array]]" : "[table]"}"
    end

    puts "\nRoot pairs found: #{analysis.root_pairs.size}"
    analysis.root_pairs.first(5).each do |pair|
      puts "  - #{pair.type}: #{pair.key_name}"
    end

    print_types_report("TreeHaver Backend Types", tree_haver_types)
  else
    puts "Parse failed!"
    puts "Errors: #{analysis.errors.inspect}"
  end
rescue => e
  puts "Error with TreeHaver: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# ============================================================
# Part 2: Direct Citrus/toml-rb Analysis
# ============================================================

puts "\n" + "-" * 80
puts "Part 2: Direct toml-rb/Citrus Backend Analysis"
puts "-" * 80

begin
  # Try to use Citrus directly via TreeHaver
  require "tree_haver"

  if TreeHaver::Backends::Citrus.available?
    puts "\nCitrus backend is available!"

    # Force Citrus backend
    TreeHaver.with_backend(:citrus) do
      parser = TreeHaver.parser_for(:toml)
      tree = parser.parse(COMPREHENSIVE_TOML)

      if tree&.root_node
        puts "Parse successful with Citrus!"
        puts "Root type: #{tree.root_node.type}"

        citrus_types = {}
        collect_node_types(tree.root_node, citrus_types)
        print_types_report("Direct Citrus Backend Types", citrus_types)

        # Check specific features
        puts "\n" + "-" * 40
        puts "Checking Array of Tables specifically:"
        puts "-" * 40

        def find_nodes_by_type(node, target_type, results = [])
          return results unless node

          node_type = node.respond_to?(:type) ? node.type.to_sym : nil
          results << node if node_type == target_type

          if node.respond_to?(:children)
            node.children.each { |child| find_nodes_by_type(child, target_type, results) }
          elsif node.respond_to?(:each)
            node.each { |child| find_nodes_by_type(child, target_type, results) }
          end

          results
        end

        # Look for array of tables
        [:table_array_element, :array_of_tables, :TableArray, :table_array].each do |potential_type|
          nodes = find_nodes_by_type(tree.root_node, potential_type)
          if nodes.any?
            puts "  Found #{nodes.size} nodes of type :#{potential_type}"
            nodes.first(2).each do |n|
              text = n.respond_to?(:text) ? n.text : n.to_s
              puts "    - #{text[0..60].inspect}"
            end
          end
        end
      else
        puts "Parse failed with Citrus"
      end
    end
  else
    puts "Citrus backend NOT available"
  end
rescue => e
  puts "Error with direct Citrus: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# ============================================================
# Part 3: Raw toml-rb Analysis (without TreeHaver adapter)
# ============================================================

puts "\n" + "-" * 80
puts "Part 3: Raw toml-rb/Citrus Parse Tree (no adapter)"
puts "-" * 80

begin
  require "toml-rb"

  parsed = TomlRB::Document.parse(COMPREHENSIVE_TOML)

  puts "\nRaw toml-rb parse successful!"
  puts "Matches count: #{parsed.matches.size}"

  # Categorize by TomlRB value types
  value_types = Hash.new { |h, k| h[k] = {count: 0, examples: []} }

  parsed.matches.each do |match|
    value = match.value
    next unless value

    type_name = value.class.name.split("::").last

    value_types[type_name][:count] += 1

    if value_types[type_name][:examples].size < 3
      example = if value.respond_to?(:full_key)
        value.full_key.to_s
      elsif value.respond_to?(:dotted_keys)
        value.dotted_keys.join(".")
      else
        match.string[0..50]
      end
      value_types[type_name][:examples] << example
    end
  end

  puts "\nTomlRB Value Types Found:"
  value_types.sort_by { |name, _| name }.each do |name, info|
    puts "\n  #{name}"
    puts "    Count: #{info[:count]}"
    puts "    Examples: #{info[:examples].join(", ")}"
  end

  # Specifically check for TableArray
  table_arrays = parsed.matches.select { |m| m.value.is_a?(TomlRB::TableArray) }
  puts "\n  TableArray nodes found: #{table_arrays.size}"
  table_arrays.each do |ta|
    puts "    - full_key: #{ta.value.full_key}"
    puts "      text: #{ta.string[0..50].inspect}"
  end
rescue LoadError => e
  puts "toml-rb not available: #{e.message}"
rescue => e
  puts "Error with raw toml-rb: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# ============================================================
# Part 4: Type Mapping Recommendations
# ============================================================

puts "\n" + "=" * 80
puts "Part 4: Type Mapping Recommendations for NodeTypeNormalizer"
puts "=" * 80

puts <<~RECOMMENDATIONS

  Based on the analysis above, update the `citrus_toml` mappings in
  NodeTypeNormalizer to match the ACTUAL types produced by the Citrus adapter.

  The TreeHaver Citrus adapter transforms raw TomlRB types into node-like
  objects. The mapping should reflect what TreeHaver's Citrus adapter produces,
  NOT the raw TomlRB class names.

  Key observations:
  1. Check if TreeHaver's Citrus adapter produces :table_array_element or
     another type name for array of tables ([[...]])
  2. Verify value types match (string, integer, float, boolean, etc.)
  3. Check how comments are represented

  If the Citrus adapter doesn't properly expose array of tables as a distinct
  type, that's a bug in TreeHaver's Citrus adapter, not in NodeTypeNormalizer.

RECOMMENDATIONS

puts "=" * 80
puts "Script complete!"
puts "=" * 80
