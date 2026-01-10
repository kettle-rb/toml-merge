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

### Changed

- tree_haver v4.0.5
  - FFI Backend improvements
  - Error handling improvements
- **Simplified dependency_tags.rb**: Removed redundant debug code
  - Removed `TOML_MERGE_DEBUG` env var handling (use `TREE_HAVER_DEBUG` instead)
  - tree_haver's debug output now respects blocked backends via `compute_blocked_backends`
  - Avoids accidentally loading MRI backend during FFI-only test runs

### Deprecated

### Removed

### Fixed

### Security

## [2.0.0] - 2026-01-09

- TAG: [v2.0.0][2.0.0t]
- COVERAGE: 88.38% -- 563/637 lines in 11 files
- BRANCH COVERAGE: 64.13% -- 177/276 branches in 11 files
- 97.03% documented

### Added

- FFI backend isolation for test suite
  - Added `bin/rspec-ffi` script to run FFI specs in isolation (before MRI backend loads)
  - Added `spec/spec_ffi_helper.rb` for FFI-specific test configuration
  - Updated Rakefile with `ffi_specs` and `remaining_specs` tasks
  - The `:test` task now runs FFI specs first, then remaining specs
- **Emitter autoload** - Added `Emitter` to module autoload list
  - Previously missing, causing `NameError: uninitialized constant Emitter` in ConflictResolver
  - Now properly autoloaded via `autoload :Emitter, "toml/merge/emitter"`
- `Backends` module with constants for backend selection
  - `Backends::TREE_SITTER` (`:tree_sitter_toml`) - Native tree-sitter parser
  - `Backends::CITRUS` (`:citrus_toml`) - Pure Ruby toml-rb parser
  - `Backends::AUTO` (`:auto`) - Auto-detect available backend
  - `Backends.validate!` and `Backends.valid?` for validation
- `SmartMerger` now accepts `backend:` parameter for explicit backend selection
  - Follows same pattern as markdown-merge
  - Auto-detects backend by default, or use `backend: Backends::CITRUS` to force pure Ruby
- `FileAnalysis` now accepts `backend:` parameter and exposes resolved backend via `#backend` attr
- `NodeWrapper` now accepts `backend:` and `document_root:` parameters for correct normalization
- **Structural normalization for Citrus backend**: Tree-sitter and Citrus backends produce different AST structures for tables:
  - Tree-sitter: Table nodes contain pairs as children
  - Citrus: Table nodes only contain header; pairs are siblings at document level
  - `NodeWrapper#pairs` now finds associated pairs regardless of AST structure
  - `NodeWrapper#content` now returns full table content on both backends
  - `NodeWrapper#effective_end_line` calculates correct end line including pairs
  - `FileAnalysis` passes `document_root` to all NodeWrappers for sibling lookups
  - This enables the merge logic to work identically across backends
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

- ast-merge v3.1.0
- tree_haver v4.0.3, adds error handling for FFI backend
- **Test suite now explicitly tests all available backend modes** - Tests previously ran with
  whatever backend was auto-selected. Now specs explicitly test up to five backend configurations:
  - `:auto` backend - Tests default user experience (backend-agnostic)
  - `:mri` backend via `TreeHaver.with_backend(:mri)` - Tests explicit tree-sitter MRI behavior
  - `:citrus` backend via `TreeHaver.with_backend(:citrus)` - Tests explicit toml-rb behavior
  - `:rust` backend via `TreeHaver.with_backend(:rust)` - Tests explicit tree-sitter Rust behavior
  - `:java` backend via `TreeHaver.with_backend(:java)` - Tests explicit tree-sitter Java behavior

  This ensures consistent behavior is verified across all backends, rather than relying
  on auto-selection which may vary by platform. Each shared example group is included
  in all contexts with appropriate dependency tags (`:toml_grammar`, `:toml_rb`,
  `:toml_parsing`, `:rust_backend`, `:java_backend`). Tests for unavailable backends
  are automatically skipped.

  **Note**: The `:java_backend` tag now correctly detects whether the Java backend can
  actually load grammars. Standard `.so` files built for MRI's tree-sitter C bindings
  are NOT compatible with java-tree-sitter. Tests will be skipped on JRuby unless
  grammar JARs from Maven Central (built for java-tree-sitter's Foreign Function Memory
  API) are available.

- **Backend handling simplified** - Let TreeHaver handle all backend selection:
  - Removed `backend:` parameter from `SmartMerger` and `FileAnalysis`
  - Removed `Backends` module entirely (was unused after removing `backend:` parameter)
  - Users control backend via TreeHaver directly (`TREE_HAVER_BACKEND` env var, `TreeHaver.backend=`, or `TreeHaver.with_backend`)
  - This ensures compatibility with all TreeHaver backends (mri, rust, ffi, java, citrus)
- **Backend naming simplified** to align with TreeHaver:
  - `NodeTypeNormalizer` mappings now keyed by `:tree_sitter` and `:citrus`
  - All native TreeHaver backends (mri, rust, ffi, java) produce tree-sitter AST format
- See `.github/COPILOT_INSTRUCTIONS.md` for comprehensive TreeHaver backend documentation
- **NodeWrapper**: Now inherits from `Ast::Merge::NodeWrapperBase`
  - Removes ~80 lines of duplicated code (initialization, line extraction, basic methods)
  - Uses `process_additional_options` hook for TOML-specific options (`backend`, `document_root`)
  - Keeps TOML-specific type predicates using `NodeTypeNormalizer`
  - Keeps Citrus structural normalization logic for `#pairs`, `#content`, `#effective_end_line`
  - Adds `#node_wrapper?` method for distinguishing from `NodeTyping::Wrapper`
- **citrus_toml mappings**: Updated to match actual Citrus/toml-rb node types
  - `table_array` → `:array_of_tables` (Citrus produces `:table_array`, not `:table_array_element`)
  - `keyvalue` → `:pair` (Citrus produces `:keyvalue`, not `:pair`)
  - Added all Citrus-specific integer types: `decimal_integer`, `hexadecimal_integer`, `octal_integer`, `binary_integer`
  - Added all Citrus-specific string types: `basic_string`, `literal_string`, `multiline_string`, `multiline_literal`
  - Added all Citrus-specific datetime types: `local_date`, `local_time`, `local_datetime`, `offset_datetime`
  - Added Citrus-specific boolean types: `true`, `false`
  - Added whitespace types: `space`, `line_break`, `indent`, `repeat`
- **FileAnalysis error handling**: Now rescues `TreeHaver::Error` instead of `TreeHaver::NotAvailable`
  - `TreeHaver::Error` inherits from `Exception`, not `StandardError`
  - `TreeHaver::NotAvailable` is a subclass of `TreeHaver::Error`, so it's also caught
  - Fixes parse error handling on TruffleRuby where Citrus backend raises `TreeHaver::Error`
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

### Removed

- **Load-time grammar registration** - TreeHaver's `parser_for` now handles grammar discovery
  and registration automatically. Removed manual `GrammarFinder` calls and warnings from
  `lib/toml/merge.rb`.

### Fixed

- **Citrus backend normalization improvements** for TruffleRuby compatibility:
  - `NodeWrapper#key_name` now strips whitespace from key text (Citrus includes trailing spaces)
  - `NodeWrapper#table_name` now strips whitespace from table header text
  - `NodeWrapper#extract_inline_table_keys` now recursively handles Citrus's deeply nested
    structure (`inline_table -> optional -> keyvalue -> keyvalue -> stripped_key -> key -> bare_key`)
  - `NodeWrapper#elements` now recursively handles Citrus's array structure where elements
    are nested in `array_elements -> repeat -> indent -> decimal_integer` chains
  - Both methods now correctly extract all values instead of just the first one
  - `NodeWrapper#value_node` now skips Citrus internal nodes (`whitespace`, `unknown`, `space`)
  - All `NodeTypeNormalizer.canonical_type()` calls now pass `@backend` parameter for correct type mapping
  - `FileAnalysis#root_pairs` now correctly filters pairs to only include those BEFORE the first table
    (Citrus has flat AST structure where all pairs are document siblings)
  - `MergeResult#add_node` now uses `effective_end_line` to include table pairs on Citrus backend
  - `TableMatchRefiner#table_node?` now uses node's backend for correct type checking
  - Test helper `parse_toml` now uses `FileAnalysis` for proper backend detection
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
[2.0.1]: https://github.com/kettle-rb/toml-merge/compare/v1.0.0...v2.0.1
[2.0.1t]: https://github.com/kettle-rb/toml-merge/releases/tag/v2.0.1
[2.0.0]: https://github.com/kettle-rb/toml-merge/compare/v1.0.0...v2.0.0
[2.0.0t]: https://github.com/kettle-rb/toml-merge/releases/tag/v2.0.0
[1.0.0]: https://github.com/kettle-rb/toml-merge/compare/772a5f5802ce518f2e2c83a561eb583ed634bac4...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/toml-merge/tags/v1.0.0
