# frozen_string_literal: true

module TomlParsingHelper
  # Parse TOML source and return a NodeWrapper for the root or specified node type
  #
  # @param source [String] TOML source code
  # @param node_type [String, nil] Optional node type to extract (e.g., 'table', 'pair')
  # @return [Toml::Merge::NodeWrapper, nil] Wrapped node
  def parse_toml(source, node_type: nil)
    return unless toml_available?

    # Use FileAnalysis to get proper backend detection
    analysis = Toml::Merge::FileAnalysis.new(source)
    return unless analysis.valid?

    lines = source.lines.map(&:chomp)
    root = analysis.ast.root_node
    backend = analysis.backend

    if node_type
      # Find the first child of the specified type (checking both raw and canonical types)
      node = find_node_by_type(root, node_type, backend)
      return unless node

      Toml::Merge::NodeWrapper.new(
        node,
        lines: lines,
        source: source,
        backend: backend,
        document_root: root,
      )
    else
      # Return root document wrapper
      Toml::Merge::NodeWrapper.new(
        root,
        lines: lines,
        source: source,
        backend: backend,
        document_root: root,
      )
    end
  end

  # Find the first node of a specific type in the tree
  # Checks both raw type and canonical type for cross-backend compatibility
  #
  # @param node [TreeHaver::Node] Node to search
  # @param type [String] Type to find (raw or canonical)
  # @param backend [Symbol] Backend for type normalization
  # @return [TreeHaver::Node, nil]
  def find_node_by_type(node, type, backend = nil)
    type_sym = type.to_sym
    node_type_sym = node.type.to_sym
    canonical = backend ? Toml::Merge::NodeTypeNormalizer.canonical_type(node_type_sym, backend) : node_type_sym

    # Match on either raw type or canonical type
    return node if node_type_sym == type_sym || canonical == type_sym

    node.each do |child|
      result = find_node_by_type(child, type, backend)
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
end
