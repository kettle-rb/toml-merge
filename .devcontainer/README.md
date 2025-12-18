# Devcontainer Setup

This devcontainer is configured to automatically install tree-sitter and build the tree-sitter-toml grammar.

## How It Works

1. **devcontainer.json** - Defines the container image and calls the `apt-install` feature
2. **apt-install/install.sh** - Runs during container creation, installs dependencies and calls the tree-sitter setup script
3. **../.github/scripts/ubuntu/setup-tree-sitter.sh** - Shared script that works in both devcontainer and GitHub Actions

## Workspace Path Handling

The setup script supports a `--workspace` flag to specify the workspace root path:

- **GitHub Actions**: Uses default `/workspaces/toml-merge/` (matching GHA structure)
- **Devcontainer**: Auto-detects the actual workspace path and passes it via `--workspace=<path>`

This allows the same script to work in both environments.

## Troubleshooting

If the automatic setup fails, you can:

### 1. Check the setup log
```bash
cat /tmp/tree-sitter-setup.log
```

### 2. Verify what was installed
```bash
ls -la /usr/local/lib/libtree-sitter*.so
ldconfig -p | grep tree-sitter
```

### 3. Run the manual setup script
```bash
sudo bash .devcontainer/manual-tree-sitter-setup.sh
```

### 4. Test tree_haver can find the grammar
```bash
ruby -e "
require 'bundler/setup'
require 'tree_haver'
finder = TreeHaver::GrammarFinder.new(:toml)
puts 'Path: ' + (finder.find_library_path || 'NOT FOUND')
puts 'Available: ' + finder.available?.to_s
"
```

### 5. Test parsing with tree-sitter
```bash
ruby -e "
require 'bundler/setup'
require 'tree_haver'
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse('[package]\nname = \"test\"')
puts 'Root type: ' + tree.root_node.type.to_s
"
```

### 6. Test parsing with Citrus fallback (toml-rb)
```bash
TREE_SITTER_TOML_PATH='' ruby -e "
require 'bundler/setup'
require 'tree_haver'
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.toml
tree = parser.parse('[package]\nname = \"test\"')
puts 'Root type: ' + tree.root_node.type.to_s
puts 'Backend: ' + parser.backend.to_s
"
```

## Environment Variables

You can control tree-sitter behavior with environment variables:

- `TREE_SITTER_TOML_PATH` - Override toml grammar location
- `TREE_SITTER_RUNTIME_LIB` - Override tree-sitter runtime library location

To disable tree-sitter for TOML and force Citrus (toml-rb) fallback:
```bash
TREE_SITTER_TOML_PATH='' ruby script.rb
```

## Rebuilding the Container

If you make changes to the setup scripts, rebuild the devcontainer:

1. In RubyMine: **Tools > DevContainer > Rebuild Container**
2. Or from command palette: **Remote-Containers: Rebuild Container**

