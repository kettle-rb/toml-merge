#!/bin/bash
set -e

# Setup script for tree-sitter dependencies (Ubuntu/Debian)
# Works for both GitHub Actions (with --sudo flag) and devcontainer (without --sudo flag)

SUDO=""
if [[ "$1" == "--sudo" ]]; then
  SUDO="sudo"
fi

echo "Installing tree-sitter system library and dependencies..."
$SUDO apt-get update -y
$SUDO apt-get install -y \
  build-essential \
  pkg-config \
  libtree-sitter-dev \
  tree-sitter-cli \
  wget \
  gcc \
  g++ \
  make \
  zlib1g-dev \
  libssl-dev \
  libreadline-dev \
  libyaml-dev \
  libxml2-dev \
  libxslt1-dev \
  libcurl4-openssl-dev \
  software-properties-common \
  libffi-dev

echo "Building and installing tree-sitter-toml..."
cd /tmp
wget -q https://github.com/tree-sitter/tree-sitter-toml/archive/refs/heads/master.zip
unzip -q master.zip
cd tree-sitter-toml-master

# Compile both parser.c and scanner.c
gcc -fPIC -I./src -c src/parser.c -o parser.o
gcc -fPIC -I./src -c src/scanner.c -o scanner.o

# Link both object files into the shared library
gcc -shared -o libtree-sitter-toml.so parser.o scanner.o

# Install to system
$SUDO cp libtree-sitter-toml.so /usr/local/lib/
$SUDO ldconfig

echo ""
echo "Tree-sitter setup complete!"
echo ""
echo "Detected library paths:"

# Detect and report tree-sitter runtime library location
if [ -f /usr/lib/x86_64-linux-gnu/libtree-sitter.so.0 ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib/x86_64-linux-gnu/libtree-sitter.so.0"
elif [ -f /usr/lib/x86_64-linux-gnu/libtree-sitter.so ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib/x86_64-linux-gnu/libtree-sitter.so"
elif [ -f /usr/lib/libtree-sitter.so.0 ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib/libtree-sitter.so.0"
elif [ -f /usr/lib/libtree-sitter.so ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib/libtree-sitter.so"
else
  echo "  WARNING: Could not find libtree-sitter runtime library!"
fi

echo "  TREE_SITTER_TOML_PATH=/usr/local/lib/libtree-sitter-toml.so"
