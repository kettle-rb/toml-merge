#!/bin/bash
# Manual tree-sitter setup script for devcontainer debugging
# Run this if the automatic setup failed

set -e

echo "=== Manual Tree-Sitter Setup for TOML ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root in the devcontainer"
  echo "Try: sudo bash .devcontainer/manual-tree-sitter-setup.sh"
  exit 1
fi

echo "1. Checking for existing tree-sitter installation..."
if ldconfig -p | grep -q libtree-sitter; then
  echo "   ✓ tree-sitter runtime found"
  ldconfig -p | grep libtree-sitter
else
  echo "   ✗ tree-sitter runtime NOT found"
  echo "   Installing libtree-sitter-dev..."
  apt-get update
  apt-get install -y libtree-sitter-dev
fi

echo ""
echo "2. Building tree-sitter-toml from source..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
echo "   Working in: $TMPDIR"

cd "$TMPDIR"
wget -q https://github.com/tree-sitter-grammars/tree-sitter-toml/archive/refs/heads/master.zip
unzip -q master.zip
cd tree-sitter-toml-master

echo "   Compiling parser.c..."
gcc -fPIC -I./src -c src/parser.c -o parser.o

echo "   Compiling scanner.c..."
gcc -fPIC -I./src -c src/scanner.c -o scanner.o

echo "   Linking shared library..."
gcc -shared -o libtree-sitter-toml.so parser.o scanner.o

echo "   Installing to /usr/local/lib/..."
cp libtree-sitter-toml.so /usr/local/lib/

echo "   Running ldconfig..."
ldconfig

echo ""
echo "3. Verification:"
if [ -f /usr/local/lib/libtree-sitter-toml.so ]; then
  echo "   ✓ /usr/local/lib/libtree-sitter-toml.so exists"
  ls -lh /usr/local/lib/libtree-sitter-toml.so
else
  echo "   ✗ ERROR: File not found!"
  exit 1
fi

if ldconfig -p | grep -q libtree-sitter-toml; then
  echo "   ✓ ldconfig can find libtree-sitter-toml.so"
  ldconfig -p | grep libtree-sitter-toml
else
  echo "   ✗ WARNING: ldconfig cannot find the library"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now test with:"
echo "  ruby -e \"require 'bundler/setup'; require 'tree_haver'; puts TreeHaver::GrammarFinder.new(:toml).find_library_path\""
echo ""

