# AGENTS.md - toml-merge Development Guide

## 🎯 Project Overview

`toml-merge` is a **format-specific implementation of the `*-merge` gem family** for TOML files. It provides intelligent TOML file merging using AST analysis with support for multiple parser backends (tree-sitter, Citrus, Parslet).

**Core Philosophy**: Intelligent TOML merging that preserves structure, comments, and formatting while applying updates from templates.

**Repository**: https://github.com/kettle-rb/toml-merge
**Current Version**: 2.0.1
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Not Visible

**CRITICAL**: AI agents using `run_in_terminal` almost never see the command output. The terminal tool sends commands to a persistent Copilot terminal, but output is frequently lost or invisible to the agent.

**Workaround**: Always redirect output to a file in the project's local `tmp/` directory, then read it back with `read_file`:

```bash
bundle exec rspec spec/some_spec.rb > tmp/test_output.txt 2>&1
```

**NEVER** use `/tmp` or other system directories — always use the project's own `tmp/` directory.

### direnv Requires Separate `cd` Command

**CRITICAL**: Never chain `cd` with other commands via `&&`. The `direnv` environment won't initialize until after all chained commands finish. Run `cd` alone first:

✅ **CORRECT**:
```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/toml-merge
```
```bash
bundle exec rspec > tmp/test_output.txt 2>&1
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/toml-merge && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

Use `read_file`, `list_dir`, `grep_search`, `file_search` instead of terminal commands for gathering information. Only use terminal for running tests, installing dependencies, and git operations.

### grep_search Cannot Search Nested Git Projects

This project is a nested git project inside the `ast-merge` workspace. The `grep_search` tool **cannot** search inside it. Use `read_file` and `list_dir` instead.

### NEVER Pipe Test Commands Through head/tail

Always redirect to a file in `tmp/` instead of truncating output.

## 🏗️ Architecture: Format-Specific Implementation

### What toml-merge Provides

- **`Toml::Merge::SmartMerger`** – TOML-specific SmartMerger implementation
- **`Toml::Merge::FileAnalysis`** – TOML file analysis with table/pair extraction
- **`Toml::Merge::NodeWrapper`** – Wrapper for TOML AST nodes (tables, pairs, arrays)
- **`Toml::Merge::MergeResult`** – TOML-specific merge result
- **`Toml::Merge::ConflictResolver`** – TOML conflict resolution
- **`Toml::Merge::FreezeNode`** – TOML freeze block support
- **`Toml::Merge::TableMatchRefiner`** – TOML table matching refinement
- **`Toml::Merge::NodeTypeNormalizer`** – Cross-backend type normalization

### Key Dependencies

| Gem | Role |
|-----|------|
| `ast-merge` (~> 4.0) | Base classes and shared infrastructure |
| `tree_haver` (~> 5.0) | Unified parser adapter (tree-sitter, Citrus, Parslet) |
| `version_gem` (~> 1.1) | Version management |

### Parser Backend Support

toml-merge works with multiple TOML parser backends via TreeHaver:

| Backend | Parser | Platform | Notes |
|---------|--------|----------|-------|
| `:mri` | tree-sitter-toml | MRI only | Best performance, requires native library |
| `:rust` | tree-sitter-toml | MRI only | Rust implementation via tree_stump |
| `:citrus` | citrus + toml-rb | All platforms | Pure Ruby, good compatibility |
| `:parslet` | parslet + toml | All platforms | Pure Ruby, alternative parser |

## 📁 Project Structure

```
lib/toml/merge/
├── smart_merger.rb          # Main SmartMerger implementation
├── file_analysis.rb         # TOML file analysis (tables, pairs)
├── node_wrapper.rb          # AST node wrapper
├── merge_result.rb          # Merge result object
├── conflict_resolver.rb     # Conflict resolution
├── freeze_node.rb           # Freeze block support
├── table_match_refiner.rb   # Table matching refinement
├── node_type_normalizer.rb  # Cross-backend type mapping
├── debug_logger.rb          # Debug logging
└── version.rb

spec/toml/merge/
├── smart_merger_spec.rb
├── file_analysis_spec.rb
├── node_wrapper_spec.rb
├── table_match_refiner_spec.rb
└── integration/
```

## 🔧 Development Workflows

### Running Tests

```bash
# Full suite (required for coverage thresholds)
bundle exec rspec

# Single file (disable coverage threshold check)
K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/toml/merge/smart_merger_spec.rb

# Specific backend tests
bundle exec rspec --tag mri_backend
bundle exec rspec --tag citrus_backend
bundle exec rspec --tag parslet_backend
```

**Note**: Always run commands in the project root (`/home/pboling/src/kettle-rb/ast-merge/vendor/toml-merge`). Allow `direnv` to load environment variables first by doing a plain `cd` before running commands.

### Coverage Reports

```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/toml-merge
bin/rake coverage && bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `.envrc`, loaded via `direnv allow`):
- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE=100` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH=82` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

### Code Quality

```bash
bundle exec rake reek
bundle exec rake rubocop_gradual
```

## 📝 Project Conventions

### API Conventions

#### SmartMerger API
- `merge` – Returns a **String** (the merged TOML content)
- `merge_result` – Returns a **MergeResult** object
- `to_s` on MergeResult returns the merged content as a string

#### TOML-Specific Features

**Table Matching**:
```ruby
merger = Toml::Merge::SmartMerger.new(template_toml, dest_toml)
result = merger.merge
```

**Freeze Blocks**:
```toml
[server]
# toml-merge:freeze
port = 8080  # Custom port, don't override
# toml-merge:unfreeze
host = "localhost"
```

**Node Type Normalization**:
- Handles differences between tree-sitter (`table`), Citrus (`table`), and Parslet (`table`) backends
- Provides canonical type names for consistent matching

### kettle-dev Tooling

This project uses `kettle-dev` for gem maintenance automation:

- **Rakefile**: Sourced from kettle-dev template
- **CI Workflows**: GitHub Actions and GitLab CI managed via kettle-dev
- **Releases**: Use `kettle-release` for automated release process

### Version Requirements
- Ruby >= 3.2.0 (gemspec), developed against Ruby 4.0.1 (`.tool-versions`)
- `ast-merge` >= 4.0.0 required
- `tree_haver` >= 5.0.3 required

## 🧪 Testing Patterns

### TreeHaver Dependency Tags

All spec files use TreeHaver RSpec dependency tags for conditional execution:

**Available tags**:
- `:toml_grammar` – Requires TOML grammar (any backend)
- `:mri_backend` – Requires tree-sitter MRI backend
- `:rust_backend` – Requires tree-sitter Rust backend
- `:citrus_backend` – Requires Citrus backend
- `:parslet_backend` – Requires Parslet backend
- `:toml_parsing` – Requires any TOML parser

✅ **CORRECT** – Use dependency tag on describe/context/it:
```ruby
RSpec.describe Toml::Merge::SmartMerger, :toml_grammar do
  # Skipped if no TOML parser available
end

it "parses with tree-sitter", :mri_backend, :toml_grammar do
  # Skipped if tree-sitter not available
end

context "when comparing backends", :citrus_backend, :parslet_backend do
  # Skipped unless both backends available
end
```

❌ **WRONG** – Never use manual skip checks:
```ruby
before do
  skip "Requires tree-sitter" unless tree_sitter_available?  # DO NOT DO THIS
end
```

### Backend Isolation

**CRITICAL**: Tests must respect backend isolation to prevent FFI/MRI conflicts:

```ruby
# Use TreeHaver.with_backend to ensure backend isolation
TreeHaver.with_backend(:mri) do
  analysis = Toml::Merge::FileAnalysis.new(toml_source)
end
```

### Shared Examples

toml-merge uses shared examples from `ast-merge`:

```ruby
it_behaves_like "Ast::Merge::FileAnalyzable"
it_behaves_like "Ast::Merge::ConflictResolverBase"
it_behaves_like "a reproducible merge", "scenario_name", { preference: :template }
```

## 🔍 Critical Files

| File | Purpose |
|------|---------|
| `lib/toml/merge/smart_merger.rb` | Main TOML SmartMerger implementation |
| `lib/toml/merge/file_analysis.rb` | TOML file analysis and table extraction |
| `lib/toml/merge/node_wrapper.rb` | TOML node wrapper with type-specific methods |
| `lib/toml/merge/table_match_refiner.rb` | TOML table matching refinement |
| `lib/toml/merge/node_type_normalizer.rb` | Cross-backend type normalization |
| `spec/spec_thin_helper.rb` | Test suite entry point with TreeHaver integration |
| `spec/support/dependency_tags.rb` | TreeHaver dependency tag integration |
| `.envrc` | Coverage thresholds and backend configuration |

## 🚀 Common Tasks

```bash
# Run all specs with coverage
bundle exec rake spec

# Generate coverage report
bundle exec rake coverage

# Check code quality
bundle exec rake reek
bundle exec rake rubocop_gradual

# Run with specific backend
TREE_HAVER_BACKEND=citrus bundle exec rspec

# Prepare and release
kettle-changelog && kettle-release
```

## 🌊 Integration Points

- **`ast-merge`**: Inherits base classes (`SmartMergerBase`, `FileAnalyzable`, etc.)
- **`tree_haver`**: Multi-backend TOML parsing (tree-sitter, Citrus, Parslet)
- **RSpec**: Full integration via `ast/merge/rspec` and `tree_haver/rspec`
- **SimpleCov**: Coverage tracked for `lib/**/*.rb`; spec directory excluded

## 💡 Key Insights

1. **Multi-backend support**: toml-merge works with 4 different TOML parsers; use backend tags to test all
2. **Backend isolation is critical**: Always use `TreeHaver.with_backend` to prevent FFI/MRI conflicts
3. **Node type normalization**: Different backends use different node type names; `NodeTypeNormalizer` provides canonical types
4. **Table matching**: TOML tables are matched by name; nested tables are handled hierarchically
5. **Freeze blocks use `# toml-merge:freeze`**: Language-specific comment syntax
6. **Never use manual skip checks**: Always use TreeHaver dependency tags (`:toml_grammar`, `:mri_backend`, etc.)
7. **Backend conflicts can cause segfaults**: The TreeHaver backend protection system prevents mixing FFI and MRI backends

## 🚫 Common Pitfalls

1. **NEVER mix FFI and MRI backends** – Use `TreeHaver.with_backend` for isolation
2. **NEVER use manual skip checks** – Use dependency tags (`:toml_grammar`, `:mri_backend`)
3. **NEVER assume a specific backend** – Write tests that work with any TOML parser
4. **Do NOT load vendor gems** – They are not part of this project; they do not exist in CI
5. **Use `tmp/` for temporary files** – Never use `/tmp` or other system directories
6. **Do NOT chain `cd` with `&&`** – Run `cd` as a separate command so `direnv` loads ENV

## 🔧 TOML-Specific Notes

### Table Structures
```toml
# Simple table
[server]
port = 8080

# Nested table (dot notation)
[server.ssl]
enabled = true

# Nested table (bracket notation)
[database]
[database.connection]
timeout = 30

# Array of tables
[[servers]]
name = "alpha"

[[servers]]
name = "beta"
```

### Merge Behavior
- **Tables**: Matched by full path (`server.ssl`)
- **Pairs**: Matched by key name within table
- **Arrays**: Can be merged or replaced based on preference
- **Comments**: Preserved when attached to tables/pairs
- **Freeze blocks**: Protect customizations from template updates
