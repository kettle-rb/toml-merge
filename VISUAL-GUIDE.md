# Visual Guide: toml-merge + tree_haver v2 + toml-rb

## The Complete Flow

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  toml-merge Application                          ┃
┃  ┌──────────────────────────────────────────┐    ┃
┃  │ lib/toml/merge/file_analysis.rb          │    ┃
┃  │                                           │    ┃
┃  │  parser = TreeHaver::Parser.new          │    ┃
┃  │  parser.language = TreeHaver::Language.toml    ┃
┃  │  @ast = parser.parse(@source)            │    ┃
┃  │  @ast.root_node.each { |node| ... }      │    ┃
┃  │                                           │    ┃
┃  │  ← Same code for ALL backends! →         │    ┃
┃  └──────────────────────────────────────────┘    ┃
┗━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                        ↓
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  tree_haver v2 (Backend Framework)               ┃
┃  ┌──────────────────────────────────────────┐    ┃
┃  │ TreeHaver::Parser                        │    ┃
┃  │ TreeHaver::Tree   (unified wrapper)      │    ┃
┃  │ TreeHaver::Node   (unified wrapper)      │    ┃
┃  │ TreeHaver::Point  (unified wrapper)      │    ┃
┃  │                                           │    ┃
┃  │ def backend_module                       │    ┃
┃  │   # Auto-select best available backend   │    ┃
┃  │   if tree-sitter available?              │    ┃
┃  │     return TreeSitter backend            │    ┃
┃  │   elsif citrus available?                │    ┃
┃  │     return Citrus backend                │    ┃
┃  │   end                                     │    ┃
┃  └──────────────────────────────────────────┘    ┃
┗━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┛
                    ↓           ↓
      ┏━━━━━━━━━━━━━┛           ┗━━━━━━━━━━━━━━━┓
      ↓                                         ↓
┏━━━━━━━━━━━━━━━━━━━━━┓           ┏━━━━━━━━━━━━━━━━━━━━━┓
┃ tree-sitter Backends┃           ┃ Citrus Backend      ┃
┃ ┌─────────────────┐ ┃           ┃ ┌─────────────────┐ ┃
┃ │ Backends::MRI   │ ┃           ┃ │Backends::Citrus │ ┃
┃ │   (C extension) │ ┃           ┃ │  (pure Ruby)    │ ┃
┃ │                 │ ┃           ┃ │                 │ ┃
┃ │ Backends::Rust  │ ┃           ┃ │ def parse(src)  │ ┃
┃ │   (tree_stump)  │ ┃           ┃ │   match =       │ ┃
┃ │                 │ ┃           ┃ │   @grammar.parse│ ┃
┃ │ Backends::FFI   │ ┃           ┃ │   wrap(match)   │ ┃
┃ │   (JRuby)       │ ┃           ┃ │ end             │ ┃
┃ │                 │ ┃           ┃ └─────────────────┘ ┃
┃ │ Backends::Java  │ ┃           ┃          ↓          ┃
┃ │   (JRuby)       │ ┃           ┃ @grammar is what?   ┃
┃ └─────────────────┘ ┃           ┗━━━━━━━━━┳━━━━━━━━━━━┛
┃         ↓           ┃                     ↓
┃ ┌─────────────────┐ ┃           ┏━━━━━━━━━━━━━━━━━━━━━┓
┃ │Native Libraries │ ┃           ┃ toml-rb             ┃
┃ │                 │ ┃           ┃ ┌─────────────────┐ ┃
┃ │ libtree-sitter  │ ┃           ┃ │TomlRB::Document │ ┃
┃ │ .so/.dylib      │ ┃           ┃ │                 │ ┃
┃ │                 │ ┃           ┃ │ Citrus grammar  │ ┃
┃ │ libtree-sitter- │ ┃           ┃ │ for TOML syntax │ ┃
┃ │ toml.so         │ ┃           ┃ │                 │ ┃
┃ │                 │ ┃           ┃ │ .parse() method │ ┃
┃ └─────────────────┘ ┃           ┃ │ returns Citrus  │ ┃
┃                     ┃           ┃ │ ::Match tree    │ ┃
┗━━━━━━━━━━━━━━━━━━━━━┛           ┃ └─────────────────┘ ┃
                                  ┗━━━━━━━━━━━━━━━━━━━━━┛
```

## Backend Selection Flow

```
User runs: toml-merge
    ↓
tree_haver checks: ruby_tree_sitter available?
    ↓ YES → Use MRI backend (fast) ✅
    ↓ NO → Continue...
    ↓
tree_haver checks: tree_stump (Rust) available?
    ↓ YES → Use Rust backend (fast) ✅
    ↓ NO → Continue...
    ↓
tree_haver checks: FFI + libtree-sitter available?
    ↓ YES → Use FFI backend (fast) ✅
    ↓ NO → Continue...
    ↓
tree_haver checks: citrus + toml-rb available?
    ↓ YES → Use Citrus backend (pure Ruby) ✅
    ↓ NO → Error (no backend available)
```

## What toml-rb Provides

```ruby
# toml-rb gem structure
module TomlRB
  module Document  # ← This is the Citrus grammar
    extend Citrus::Grammar
    
    # Grammar rules defined in Citrus PEG syntax
    # Defines: document, table, array_of_tables, pair, etc.
    
    def self.parse(source)
      # Returns Citrus::Match (parse tree)
    end
  end
  
  # Semantic classes (not used by tree_haver directly)
  class Table
  class TableArray
  class Keyvalue
end

# tree_haver uses it like this:
grammar = TomlRB::Document
match = grammar.parse(toml_source)  # Get parse tree
# Wrap in TreeHaver::Node for unified API
```

## Comparison Table

| Aspect | tree-sitter Backends | Citrus Backend (toml-rb) |
|--------|---------------------|--------------------------|
| **Speed** | Fast (native C/Rust) | Slower (pure Ruby) |
| **Installation** | Requires native libs | No native deps |
| **Platforms** | Limited (needs compilation) | Universal (pure Ruby) |
| **Grammar Source** | libtree-sitter-toml.so | TomlRB::Document module |
| **API** | TreeHaver::Node | TreeHaver::Node (same!) |
| **Used When** | Preferred (fast) | Fallback (portable) |

## Code Path Comparison

### Path 1: tree-sitter Backend

```ruby
# toml-merge code
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse(source)

# Inside tree_haver (MRI backend)
language = load_library("/usr/lib/libtree-sitter-toml.so")
ts_tree = TreeSitter.parse(source, language)
TreeHaver::Tree.new(ts_tree, source: source)

# Result
tree.root_node  # TreeHaver::Node wrapping TreeSitter::Node
```

### Path 2: Citrus Backend (toml-rb)

```ruby
# toml-merge code (SAME AS ABOVE!)
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse(source)

# Inside tree_haver (Citrus backend)
grammar = TomlRB::Document
citrus_match = grammar.parse(source)
citrus_tree = Citrus::Tree.new(citrus_match, source)
TreeHaver::Tree.new(citrus_tree, source: source)

# Result
tree.root_node  # TreeHaver::Node wrapping Citrus::Match
```

**Notice**: toml-merge code is IDENTICAL! tree_haver handles the difference.

## Dependency Chain

```
toml-merge.gemspec:
  spec.add_dependency("tree_haver", "~> 2.0")
  spec.add_dependency("toml-rb", "~> 4.1")
      ↓
tree_haver.gemspec:
  spec.add_dependency("citrus", "~> 3.0")  # Citrus parser generator
      ↓
toml-rb.gemspec:
  spec.add_dependency("citrus", "~> 3.0")  # Uses Citrus for grammar
```

**Result**: 
- citrus gets installed (needed by both tree_haver and toml-rb)
- toml-rb gets installed (TOML grammar for Citrus)
- tree_haver can use Citrus backend with toml-rb grammar
- 100% installation success guaranteed!

## The Genius of This Design

1. **Separation of Concerns**
   - tree_haver = backend framework
   - toml-rb = TOML grammar
   - toml-merge = merge logic

2. **Reusability**
   - tree_haver's Citrus backend works for ANY language
   - Just need a Citrus grammar (toml-rb, json-rb, etc.)
   - All *-merge gems benefit

3. **Flexibility**
   - Fast when possible (tree-sitter)
   - Works everywhere (Citrus)
   - User doesn't care - it just works

4. **Simplicity**
   - toml-merge doesn't know about backends
   - tree_haver handles complexity
   - Clean, maintainable code

## Summary

**toml-rb's role**: Provides the TOML grammar (TomlRB::Document) that tree_haver's Citrus backend uses for pure Ruby parsing when tree-sitter libraries aren't available.

**Why it's brilliant**: Instead of implementing dual backends in every *-merge gem, the backend framework (tree_haver) handles it once, and language-specific grammars (toml-rb) plug in as needed.

