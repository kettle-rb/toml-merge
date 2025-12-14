# frozen_string_literal: true

module TomlParsingHelper
  # Parse TOML source and return a NodeWrapper for the root or specified node type
  #
  # @param source [String] TOML source code
  # @param node_type [String, nil] Optional node type to extract (e.g., 'table', 'pair')
  # @return [Toml::Merge::NodeWrapper, nil] Wrapped node
  def parse_toml(source, node_type: nil)
    parser_path = Toml::Merge::FileAnalysis.find_parser_path
    return unless parser_path

    # Use TreeSitter namespace (aliased to TreeHaver via compat shim)
    language = TreeSitter::Language.load("toml", parser_path)
    parser = TreeSitter::Parser.new
    parser.language = language
    tree = parser.parse_string(nil, source)

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
  # @param node [TreeSitter::Node] Node to search
  # @param type [String] Type to find
  # @return [TreeSitter::Node, nil]
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
  # @param node [TreeSitter::Node] Node to print
  # @param indent [Integer] Indentation level
  def print_node_tree(node, indent = 0)
    puts "  " * indent + node.type.to_s
    node.each { |child| print_node_tree(child, indent + 1) }
  end

  # Check if tree-sitter TOML parser is available
  #
  # @return [Boolean]
  def tree_sitter_available?
    !Toml::Merge::FileAnalysis.find_parser_path.nil?
  end
end
