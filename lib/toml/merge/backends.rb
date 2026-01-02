# frozen_string_literal: true

module Toml
  module Merge
    # Backend constants for TOML parsing.
    #
    # Backend loading and availability is handled entirely by tree_haver.
    # If a backend fails to load, tree_haver raises the appropriate error.
    # toml-merge simply passes the backend selection through.
    #
    # @example Using a specific backend
    #   merger = SmartMerger.new(template, dest, backend: Backends::TREE_SITTER)
    #
    # @example Using auto-detection
    #   merger = SmartMerger.new(template, dest, backend: Backends::AUTO)
    #
    # @see TreeHaver
    module Backends
      # Use the tree-sitter-toml backend (native parser)
      TREE_SITTER = :tree_sitter_toml

      # Use the Citrus/toml-rb backend (pure Ruby parser)
      CITRUS = :citrus_toml

      # Auto-select backend (tree_haver handles selection and fallback)
      AUTO = :auto

      # All valid backend identifiers
      VALID_BACKENDS = [TREE_SITTER, CITRUS, AUTO].freeze

      class << self
        # Validate backend is a known type (does not check availability)
        #
        # @param backend [Symbol] Backend identifier
        # @return [Symbol] The validated backend
        # @raise [ArgumentError] If backend is not recognized
        def validate!(backend)
          return backend if VALID_BACKENDS.include?(backend)

          raise ArgumentError, "Unknown backend: #{backend.inspect}. " \
            "Valid backends: #{VALID_BACKENDS.map(&:inspect).join(", ")}"
        end

        # Check if backend is a valid identifier (does not check availability)
        #
        # @param backend [Symbol] Backend identifier
        # @return [Boolean]
        def valid?(backend)
          VALID_BACKENDS.include?(backend)
        end
      end
    end
  end
end
