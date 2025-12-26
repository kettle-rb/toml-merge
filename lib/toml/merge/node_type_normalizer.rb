# frozen_string_literal: true

module Toml
  module Merge
    # Normalizes backend-specific node types to canonical TOML types.
    #
    # Uses Ast::Merge::NodeTyping::Wrapper to wrap nodes with canonical
    # merge_type, allowing portable merge rules across backends.
    #
    # ## Backends
    #
    # Currently supports:
    # - `:tree_sitter_toml` - tree-sitter-toml grammar (via ruby_tree_sitter, tree_stump, FFI)
    # - `:citrus_toml` - toml-rb gem with Citrus parser
    #
    # ## Extensibility
    #
    # New backends can be registered at runtime:
    #
    # @example Registering a new backend
    #   NodeTypeNormalizer.register_backend(:my_toml_parser, {
    #     key_value: :pair,
    #     section: :table,
    #     section_array: :array_of_tables,
    #   })
    #
    # ## Canonical Types
    #
    # The following canonical types are used for portable merge rules:
    #
    # ### Document Structure
    # - `:document` - Root document node
    # - `:table` - Table/section header `[section]`
    # - `:array_of_tables` - Array of tables `[[section]]`
    # - `:pair` - Key-value pair `key = value`
    #
    # ### Key Types
    # - `:bare_key` - Unquoted key
    # - `:quoted_key` - Quoted key `"key"` or `'key'`
    # - `:dotted_key` - Dotted key `a.b.c`
    #
    # ### Value Types
    # - `:string` - String values (basic or literal)
    # - `:integer` - Integer values
    # - `:float` - Floating point values
    # - `:boolean` - Boolean `true`/`false`
    # - `:array` - Array values `[1, 2, 3]`
    # - `:inline_table` - Inline table `{ key = value }`
    #
    # ### Date/Time Types
    # - `:datetime` - Date/time values (offset, local, date-only, time-only)
    #
    # ### Other
    # - `:comment` - Comment lines
    #
    # @see Ast::Merge::NodeTyping::Wrapper
    module NodeTypeNormalizer
      # Default backend type mappings (extensible via register_backend)
      # Maps backend-specific type symbols to canonical type symbols.
      #
      # Both tree-sitter-toml and citrus/toml-rb produce similar node types,
      # so the mappings are largely identity mappings with some normalization.
      @backend_mappings = {
        # tree-sitter-toml grammar node types
        # Reference: https://github.com/tree-sitter-grammars/tree-sitter-toml
        tree_sitter_toml: {
          # Document structure
          document: :document,
          table: :table,
          table_array_element: :array_of_tables,  # tree-sitter uses this name

          # Key-value pairs
          pair: :pair,

          # Key types
          bare_key: :bare_key,
          quoted_key: :quoted_key,
          dotted_key: :dotted_key,

          # Value types
          string: :string,
          basic_string: :string,
          literal_string: :string,
          multiline_basic_string: :string,
          multiline_literal_string: :string,
          integer: :integer,
          float: :float,
          boolean: :boolean,
          array: :array,
          inline_table: :inline_table,

          # Date/time types
          offset_date_time: :datetime,
          local_date_time: :datetime,
          local_date: :datetime,
          local_time: :datetime,

          # Other
          comment: :comment,

          # Punctuation (usually not needed for merge logic, but map them)
          "=": :equals,
          "[": :bracket_open,
          "]": :bracket_close,
          "[[": :double_bracket_open,
          "]]": :double_bracket_close,
          "{": :brace_open,
          "}": :brace_close,
          ",": :comma,
        }.freeze,

        # Citrus/toml-rb backend node types
        # These are synthesized by tree_haver's Citrus adapter
        citrus_toml: {
          # Document structure
          document: :document,
          table: :table,
          table_array_element: :array_of_tables,  # Citrus adapter uses same name

          # Key-value pairs
          pair: :pair,

          # Key types
          bare_key: :bare_key,
          quoted_key: :quoted_key,
          dotted_key: :dotted_key,

          # Value types
          string: :string,
          integer: :integer,
          float: :float,
          boolean: :boolean,
          array: :array,
          inline_table: :inline_table,

          # Date/time types (may vary based on toml-rb version)
          datetime: :datetime,
          date: :datetime,
          time: :datetime,

          # Other
          comment: :comment,

          # Punctuation
          "=": :equals,
          "[": :bracket_open,
          "]": :bracket_close,
          "[[": :double_bracket_open,
          "]]": :double_bracket_close,
          "{": :brace_open,
          "}": :brace_close,
          ",": :comma,
        }.freeze,
      }

      class << self
        # Register type mappings for a new backend.
        #
        # This allows extending toml-merge to support additional
        # TOML parsers beyond tree-sitter-toml and toml-rb.
        #
        # @param backend [Symbol] Backend identifier (e.g., :my_toml_parser)
        # @param mappings [Hash{Symbol => Symbol}] Backend type → canonical type
        # @return [Hash{Symbol => Symbol}] The frozen mappings
        #
        # @example
        #   NodeTypeNormalizer.register_backend(:my_parser, {
        #     key_value: :pair,
        #     section: :table,
        #   })
        def register_backend(backend, mappings)
          @backend_mappings[backend] = mappings.freeze
        end

        # Get the canonical type for a backend-specific type.
        #
        # If no mapping exists, returns the original type unchanged.
        # This allows backend-specific types to pass through for
        # backend-specific merge rules.
        #
        # @param backend_type [Symbol, String] The backend's node type
        # @param backend [Symbol] The backend identifier (:tree_sitter_toml or :citrus_toml)
        # @return [Symbol] Canonical type (or original if no mapping)
        #
        # @example
        #   NodeTypeNormalizer.canonical_type(:table_array_element, :tree_sitter_toml)
        #   # => :array_of_tables
        #
        #   NodeTypeNormalizer.canonical_type(:pair, :citrus_toml)
        #   # => :pair
        #
        #   NodeTypeNormalizer.canonical_type(:unknown_type, :tree_sitter_toml)
        #   # => :unknown_type (passthrough)
        def canonical_type(backend_type, backend = :tree_sitter_toml)
          return backend_type if backend_type.nil?

          # Convert to symbol for lookup since tree_haver returns string types
          type_sym = backend_type.to_sym
          @backend_mappings.dig(backend, type_sym) || type_sym
        end

        # Wrap a node with its canonical type as merge_type.
        #
        # Uses Ast::Merge::NodeTyping.with_merge_type to create a wrapper
        # that delegates all methods to the underlying node while adding
        # a canonical merge_type attribute.
        #
        # @param node [Object] The backend node to wrap
        # @param backend [Symbol] The backend identifier
        # @return [Ast::Merge::NodeTyping::Wrapper] Wrapped node with canonical merge_type
        #
        # @example
        #   # tree-sitter node with type :table_array_element becomes wrapped with merge_type :array_of_tables
        #   wrapped = NodeTypeNormalizer.wrap(ts_node, :tree_sitter_toml)
        #   wrapped.type        # => :table_array_element (original)
        #   wrapped.merge_type  # => :array_of_tables (canonical)
        #   wrapped.unwrap      # => ts_node (original node)
        def wrap(node, backend = :tree_sitter_toml)
          canonical = canonical_type(node.type, backend)
          Ast::Merge::NodeTyping.with_merge_type(node, canonical)
        end

        # Check if a type is a table type (regular or array of tables)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def table_type?(type)
          canonical = type.to_sym
          %i[table array_of_tables].include?(canonical)
        end

        # Check if a type is a value type (string, integer, etc.)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def value_type?(type)
          canonical = type.to_sym
          %i[string integer float boolean array inline_table datetime].include?(canonical)
        end

        # Check if a type is a key type
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def key_type?(type)
          canonical = type.to_sym
          %i[bare_key quoted_key dotted_key].include?(canonical)
        end

        # Check if a type is a container type (can have children)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def container_type?(type)
          canonical = type.to_sym
          %i[document table array_of_tables array inline_table].include?(canonical)
        end

        # Get all registered backends.
        #
        # @return [Array<Symbol>] Backend identifiers
        def registered_backends
          @backend_mappings.keys
        end

        # Check if a backend is registered.
        #
        # @param backend [Symbol] Backend identifier
        # @return [Boolean]
        def backend_registered?(backend)
          @backend_mappings.key?(backend)
        end

        # Get the mappings for a specific backend.
        #
        # @param backend [Symbol] Backend identifier
        # @return [Hash{Symbol => Symbol}, nil] The mappings or nil if not registered
        def mappings_for(backend)
          @backend_mappings[backend]
        end

        # Get all canonical types across all backends.
        #
        # @return [Array<Symbol>] Unique canonical type symbols
        def canonical_types
          @backend_mappings.values.flat_map(&:values).uniq
        end
      end
    end
  end
end

