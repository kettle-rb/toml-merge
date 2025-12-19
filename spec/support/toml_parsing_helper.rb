# frozen_string_literal: true

module TomlParsingHelper
  # Parse TOML source and return a NodeWrapper for the root or specified node type
  #
  # @param source [String] TOML source code
  # @param node_type [String, nil] Optional node type to extract (e.g., 'table', 'pair')
  # @return [Toml::Merge::NodeWrapper, nil] Wrapped node
  def parse_toml(source, node_type: nil)
    return unless toml_available?

    # Use TreeHaver's unified interface - handles tree-sitter and Citrus fallback
    parser = TreeHaver::Parser.new
    parser.language = TreeHaver::Language.toml
    tree = parser.parse(source)

    return if tree.nil? || tree.root_node.nil?

    lines = source.lines.map(&:chomp)

    if node_type
      # Find the first child of the specified type
      node = find_node_by_type(tree.root_node, node_type)
      return unless node

      Toml::Merge::NodeWrapper.new(node, lines: lines, source: source)
    else
      # Return root document wrapper
      Toml::Merge::NodeWrapper.new(tree.root_node, lines: lines, source: source)
    end
  end

  # Find the first node of a specific type in the tree
  #
  # @param node [TreeHaver::Node] Node to search
  # @param type [String] Type to find
  # @return [TreeHaver::Node, nil]
  def find_node_by_type(node, type)
    return node if node.type.to_s == type

    node.each do |child|
      result = find_node_by_type(child, type)
      return result if result
    end

    nil
  end

  # Debug helper to print all node types in a tree
  #
  # @param node [TreeHaver::Node] Node to print
  # @param indent [Integer] Indentation level
  def print_node_tree(node, indent = 0)
    puts "  " * indent + node.type.to_s
    node.each { |child| print_node_tree(child, indent + 1) }
  end

  # Check if TOML parsing is available (tree-sitter or Citrus)
  #
  # @return [Boolean]
  def toml_available?
    TreeHaver::Language.respond_to?(:toml)
  end

  # Alias for backwards compatibility
  alias_method :tree_sitter_available?, :toml_available?
end
