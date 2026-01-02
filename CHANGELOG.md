# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- `Backends` module with constants for backend selection
  - `Backends::TREE_SITTER` (`:tree_sitter_toml`) - Native tree-sitter parser
  - `Backends::CITRUS` (`:citrus_toml`) - Pure Ruby toml-rb parser
  - `Backends::AUTO` (`:auto`) - Auto-detect available backend
  - `Backends.validate!` and `Backends.valid?` for validation
- `SmartMerger` now accepts `backend:` parameter for explicit backend selection
  - Follows same pattern as markdown-merge
  - Auto-detects backend by default, or use `backend: Backends::CITRUS` to force pure Ruby
- `FileAnalysis` now accepts `backend:` parameter and exposes resolved backend via `#backend` attr
- `NodeWrapper` now accepts `backend:` parameter for correct canonical type resolution

- `NodeTypeNormalizer` module for backend-agnostic node type handling
  - Maps backend-specific types (e.g., `table_array_element`) to canonical types (e.g., `array_of_tables`)
  - Supports both `tree_sitter_toml` and `citrus_toml` backends with comprehensive type mappings
  - Provides helper methods: `table_type?`, `value_type?`, `key_type?`, `container_type?`
  - Extensible via `register_backend` for custom TOML parsers
  - Follows the same pattern as `markdown-merge`'s `NodeTypeNormalizer`
- `NodeWrapper#canonical_type` method returns the normalized type for a node
- Comprehensive test suite for `NodeTypeNormalizer` with 26 new specs
- `spec/support/dependency_tags.rb` for conditional test execution based on backend availability

### Changed

- **citrus_toml mappings**: Updated to match actual Citrus/toml-rb node types
  - `table_array` → `:array_of_tables` (Citrus produces `:table_array`, not `:table_array_element`)
  - `keyvalue` → `:pair` (Citrus produces `:keyvalue`, not `:pair`)
  - Added all Citrus-specific integer types: `decimal_integer`, `hexadecimal_integer`, `octal_integer`, `binary_integer`
  - Added all Citrus-specific string types: `basic_string`, `literal_string`, `multiline_string`, `multiline_literal`
  - Added all Citrus-specific datetime types: `local_date`, `local_time`, `local_datetime`, `offset_datetime`
  - Added Citrus-specific boolean types: `true`, `false`
  - Added whitespace types: `space`, `line_break`, `indent`, `repeat`
- **Dependency tags**: Refactored to use shared `TreeHaver::RSpec::DependencyTags` from tree_haver gem
  - All dependency detection is now centralized in tree_haver
  - Use `require "tree_haver/rspec"` for shared RSpec configuration
  - `TomlMergeDependencies` is now an alias to `TreeHaver::RSpec::DependencyTags`
  - Enables `TOML_MERGE_DEBUG=1` for dependency summary output
- **FileAnalysis**: Error handling now follows the standard pattern
  - Parse errors are collected but not re-raised from FileAnalysis
  - `valid?` returns false when there are errors or no AST
  - SmartMergerBase handles raising the appropriate parse error
  - Consistent with json-merge, jsonc-merge, and bash-merge implementations
- **SmartMerger**: Added `**options` for forward compatibility
  - Accepts additional options that may be added to base class in future
  - Passes all options through to `SmartMergerBase`
  - `node_typing` parameter for per-node-type merge preferences
    - Enables `preference: { default: :destination, special_type: :template }` pattern
    - Works with custom merge_types assigned via node_typing lambdas
  - `regions` and `region_placeholder` parameters for nested content merging
- **ConflictResolver**: Added `**options` for forward compatibility
  - Now passes `match_refiner` to base class instead of storing locally
- **MergeResult**: Added `**options` for forward compatibility
- **FileAnalysis**: Simplified to use `TreeHaver.parser_for` API
  - Removed 40+ lines of grammar loading boilerplate
  - Now relies on tree_haver for auto-discovery and Citrus fallback
  - `:tree_sitter_toml` RSpec tag for tree-sitter-toml grammar tests
  - `:toml_rb` RSpec tag for toml-rb/Citrus backend tests
  - `:toml_backend` RSpec tag for tests requiring any TOML backend
- **BREAKING**: `NodeWrapper` type predicates now use `NodeTypeNormalizer` for backend-agnostic type checking
  - `array_of_tables?` now correctly identifies both `table_array_element` (tree-sitter) and `array_of_tables` nodes
  - All predicates (`table?`, `pair?`, `string?`, etc.) use canonical types
  - `type?` method checks both raw and canonical types
- `FileAnalysis#tables` now uses `NodeTypeNormalizer.table_type?` for type detection
- `FileAnalysis#root_pairs` and `#integrate_nodes` use canonical type checks
- `TableMatchRefiner#table_node?` uses `NodeTypeNormalizer` for backend-agnostic table detection
- `compute_signature` method uses canonical types for consistent signatures across backends
- Rewrote `node_wrapper_spec.rb` with proper tests (removed placeholder/pending tests)
- Rewrote `table_match_refiner_spec.rb` with working tests using `:toml_backend` tag
- Updated `spec_helper.rb` load order to ensure `TreeHaver` is available for dependency detection
- **BREAKING**: Migrate from direct `TreeSitter::Language.load` to `TreeHaver` API
  - Changed `require "tree_sitter"` to `require "tree_haver"` in main module file
  - Added automatic grammar registration via `TreeHaver::GrammarFinder#register!`
  - `FileAnalysis#find_parser_path` now exclusively uses `TreeHaver::GrammarFinder`
  - `FileAnalysis#parse_toml` now uses `TreeHaver::Parser` and `TreeHaver::Language`
  - Removed legacy fallback path search (TreeHaver is now a hard requirement)
  - Updated documentation to reference `TreeHaver::Node` instead of `TreeSitter::Node`
  - Environment variable `TREE_SITTER_TOML_PATH` is still supported via TreeHaver
  - This enables support for multiple tree-sitter backends (MRI, Rust, FFI, Java) and Citrus fallback

### Fixed

- `NodeTypeNormalizer.canonical_type` now defaults to `:tree_sitter_toml` backend when no backend is specified
  - Added `DEFAULT_BACKEND` constant and overrode `canonical_type` and `wrap` methods
  - Fixes issue where calling `canonical_type(:table_array_element)` without a backend argument would passthrough instead of mapping to `:array_of_tables`
  - Value type predicates (`string?`, `integer?`, `float?`, `boolean?`, `array?`, `inline_table?`, `datetime?`) now work correctly
- Consolidated duplicate `describe` blocks in spec files (`file_analysis_spec.rb`, `merge_result_spec.rb`, `node_wrapper_spec.rb`)
- Fixed lint violations: added missing expectations to tests, used safe navigation where appropriate
- No longer warns about missing TOML grammar when the grammar file exists but tree-sitter runtime is unavailable
  - This is expected behavior when using non-tree-sitter backends (Citrus, Prism, etc.)
  - Warning now only appears when the grammar file is actually missing

## [1.0.0] - 2025-12-19

- TAG: [v1.0.0][1.0.0t]
- COVERAGE: 94.05% -- 506/538 lines in 9 files
- BRANCH COVERAGE: 76.64% -- 164/214 branches in 9 files
- 96.55% documented

### Added

- Initial release
- Added support for pure Ruby TOML parsing via tree_haver v3 Citrus backend with toml-rb
  - Automatically registers both tree-sitter-toml (native, fast) and toml-rb (pure Ruby) grammars
  - TreeHaver auto-selects best available backend (tree-sitter preferred, Citrus fallback)
  - Enables TOML parsing on platforms without native library support
  - Can force Citrus backend via `TREE_HAVER_BACKEND=citrus` environment variable
- Added graceful error handling when neither tree-sitter-toml nor toml-rb are available

[Unreleased]: https://github.com/kettle-rb/toml-merge/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/kettle-rb/toml-merge/compare/v1.0.0...v2.0.0
[2.0.0t]: https://github.com/kettle-rb/toml-merge/releases/tag/v2.0.0
[1.0.0]: https://github.com/kettle-rb/toml-merge/compare/772a5f5802ce518f2e2c83a561eb583ed634bac4...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/toml-merge/tags/v1.0.0
