# Tree-Sitter Setup Scripts

This directory contains scripts for installing tree-sitter dependencies in both GitHub Actions (GHA) and devcontainer environments.

## Overview

The `setup-tree-sitter.sh` script is designed to work seamlessly in multiple environments:

- **GitHub Actions workflows**: Runs as a non-root user on Ubuntu runners
- **Devcontainer build**: Runs as root via apt-install feature
- **Devcontainer postCreate**: Runs as non-root user after container creation
- **Local testing**: Can be run manually with or without sudo

## Dual-Environment Design

### Auto-Detection

The script automatically detects whether it needs to use `sudo` by checking if it's running as root:

```bash
if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi
```

This means:
- Running as root (UID 0) → Uses empty string for sudo commands
- Running as non-root → Uses "sudo" prefix for system commands
- Explicit `--sudo` flag → Overrides auto-detection (optional)

### Usage Examples

**GitHub Actions** (auto-detects non-root):
```yaml
- name: Install tree-sitter dependencies
  run: .github/scripts/ubuntu/setup-tree-sitter.sh
```

**Devcontainer apt-install** (runs as root):
```bash
bash "$SETUP_SCRIPT" --workspace="$WORKSPACE_ROOT"
```

**Devcontainer postCreateCommand** (auto-detects):
```json
"postCreateCommand": "bash ${containerWorkspaceFolder}/.github/scripts/ubuntu/setup-tree-sitter.sh --workspace=${containerWorkspaceFolder} && bundle update --bundler"
```

## Options

- `--sudo`: Force use of sudo (optional, auto-detected by default)
- `--cli`: Install tree-sitter-cli via npm (optional)
- `--build`: Build tree-sitter from source instead of using distro packages (optional)
- `--workspace PATH`: Workspace root path (informational/debugging only, not used in logic)

## What Gets Installed

The script installs:

1. **tree-sitter runtime library**: Either via `apt-get install libtree-sitter-dev` or built from source
2. **Grammar-specific parser**: Downloads, compiles, and installs the language grammar (e.g., tree-sitter-toml)
3. **tree-sitter CLI** (optional): Via npm if `--cli` flag is used

## Troubleshooting

### Checking Installation

After running the script, verify the installation:

```bash
# Check for runtime library
ldconfig -p | grep libtree-sitter

# Check for grammar library (replace 'toml' with your grammar)
ls -lh /usr/local/lib/libtree-sitter-toml.so

# Test with Ruby (requires tree_haver gem)
ruby -e "require 'bundler/setup'; require 'tree_haver'; puts TreeHaver::GrammarFinder.new(:toml).find_library_path"
```

### Common Issues

**Issue**: Script hangs or doesn't produce output in GHA
- **Cause**: Terminal output visibility bug in tooling
- **Solution**: Check the workflow run logs directly in GitHub, or trigger manually and review

**Issue**: Library not found at runtime
- **Cause**: `LD_LIBRARY_PATH` not set correctly
- **Solution**: Ensure workflow sets environment variables:
  ```yaml
  env:
    LD_LIBRARY_PATH: "/usr/local/lib:/usr/lib/x86_64-linux-gnu:/usr/lib"
    TREE_SITTER_RUNTIME_LIB: "/usr/lib/x86_64-linux-gnu/libtree-sitter.so.0"
    TREE_SITTER_TOML_PATH: "/usr/local/lib/libtree-sitter-toml.so"
  ```

**Issue**: Permission denied errors
- **Cause**: Script needs sudo but auto-detection failed
- **Solution**: Explicitly pass `--sudo` flag, or check if running in restricted environment

## Argument Parsing Fix (December 2024)

Previous versions of this script had a critical bug in argument parsing:

```bash
# BROKEN (don't use this pattern)
for arg in "$@"; do
  case $arg in
    --sudo)
      SUDO="sudo"
      shift  # ❌ shift doesn't work inside for loop
      ;;
  esac
done
```

The `shift` command doesn't affect the loop iteration in `for arg in "$@"`, causing incorrect parsing.

**Fixed version** uses a `while` loop:

```bash
# CORRECT
while [[ $# -gt 0 ]]; do
  case $1 in
    --sudo)
      SUDO="sudo"
      shift  # ✅ shift works correctly in while loop
      ;;
  esac
done
```

## Related Files

- `.devcontainer/devcontainer.json`: Calls this script in postCreateCommand
- `.devcontainer/apt-install/install.sh`: Calls this script during container build
- `.devcontainer/manual-tree-sitter-setup.sh`: Manual fallback script for debugging
- `.github/workflows/*.yml`: GHA workflows that call this script

## Propagation to Other Gems

This script pattern has been propagated to all gems that use tree-sitter:

- `json-merge` → tree-sitter-json
- `jsonc-merge` → tree-sitter-jsonc
- `bash-merge` → tree-sitter-bash
- `toml-merge` → tree-sitter-toml

Each gem has its own copy with the appropriate grammar name updated.

