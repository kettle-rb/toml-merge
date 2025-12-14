#!/bin/bash
set -euo pipefail

# Setup script for tree-sitter dependencies on Universal Blue (Fedora Atomic/Silverblue/Kinoite etc.)
# - If running on an rpm-ostree system, we will layer required toolchain packages.
# - Layering requires a reboot to take effect. This script will detect that and print clear instructions.
# - After required packages are available, it will build and install tree-sitter-toml into /usr/local/lib.
# - Works in CI or locally.
# Options:
#   --sudo: Use sudo for package installation commands
#   --cli:  Install tree-sitter-cli via npm (optional)

SUDO=""
INSTALL_CLI=false

for arg in "$@"; do
  case $arg in
    --sudo)
      SUDO="sudo"
      ;;
    --cli)
      INSTALL_CLI=true
      ;;
  esac
done

have_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "[universal-blue] Starting setup for tree-sitter and toolchain..."

# Determine if we're on rpm-ostree based system
if have_cmd rpm-ostree && rpm-ostree status >/dev/null 2>&1; then
  echo "[universal-blue] Detected rpm-ostree based system."

  # Packages required to build and run
  # Note: package names are Fedora equivalents of the Debian packages used in the Ubuntu script
  PKGS=(
    gcc gcc-c++ make wget
    pkgconf-pkg-config
    zlib-devel
    openssl-devel
    readline-devel
    libyaml-devel
    libxml2-devel
    libxslt-devel
    libcurl-devel
    libffi-devel
    tree-sitter tree-sitter-devel tree-sitter-cli
  )

  echo "[universal-blue] Layering packages via rpm-ostree: ${PKGS[*]}"
  $SUDO rpm-ostree install -y "${PKGS[@]}" || true

  echo ""
  echo "[universal-blue] If packages were just layered, a reboot is required before building."
  echo "Next steps:"
  echo "  1) Reboot your machine (required for layered packages)."
  echo "  2) Re-run this script to perform the tree-sitter-toml build/install step."
  echo ""

  # If gcc is not available yet, we bail out now (pre-reboot phase)
  if ! have_cmd gcc; then
    echo "[universal-blue] Toolchain not yet active (likely pre-reboot). Exiting early."
    exit 0
  fi
else
  echo "[universal-blue] rpm-ostree not detected. Assuming classic Fedora or containerized environment."
  if have_cmd dnf; then
    echo "[universal-blue] Installing build/runtime deps via dnf..."
    $SUDO dnf install -y \
      gcc gcc-c++ make wget \
      pkgconf-pkg-config \
      zlib-devel \
      openssl-devel \
      readline-devel \
      libyaml-devel \
      libxml2-devel \
      libxslt-devel \
      libcurl-devel \
      libffi-devel \
      tree-sitter tree-sitter-devel
  else
    echo "[universal-blue] ERROR: Neither rpm-ostree nor dnf is available."
    echo "Please install required packages using your environment's package manager, then re-run."
    exit 1
  fi
fi

# Install tree-sitter CLI via npm (optional)
if [ "$INSTALL_CLI" = true ]; then
  echo "Installing tree-sitter-cli via npm..."
  $SUDO npm install -g tree-sitter-cli
else
  echo "Skipping tree-sitter-cli installation (use --cli flag to install)"
fi

echo "[universal-blue] Building and installing tree-sitter-toml..."
cd /tmp
wget -q https://github.com/tree-sitter-grammars/tree-sitter-toml/archive/refs/heads/master.zip
unzip -q -o master.zip
cd tree-sitter-toml-master

# Compile parser and scanner
gcc -fPIC -I./src -c src/parser.c -o parser.o
gcc -fPIC -I./src -c src/scanner.c -o scanner.o

# Link shared library
gcc -shared -o libtree-sitter-toml.so parser.o scanner.o

# Install to a writable system path on atomic Fedora (usr/local is writable)
$SUDO cp libtree-sitter-toml.so /usr/local/lib/

# ldconfig may not exist in some minimal containers; ignore failure
if have_cmd ldconfig; then
  $SUDO ldconfig || true
fi

echo ""
echo "[universal-blue] Tree-sitter setup complete!"
echo ""
echo "Detected library paths (set these if needed):"

if [ -f /usr/lib64/libtree-sitter.so.0 ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib64/libtree-sitter.so.0"
elif [ -f /usr/lib64/libtree-sitter.so ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib64/libtree-sitter.so"
elif [ -f /usr/lib/libtree-sitter.so.0 ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib/libtree-sitter.so.0"
elif [ -f /usr/lib/libtree-sitter.so ]; then
  echo "  TREE_SITTER_RUNTIME_LIB=/usr/lib/libtree-sitter.so"
else
  echo "  WARNING: Could not find libtree-sitter runtime library!"
fi

echo "  TREE_SITTER_TOML_PATH=/usr/local/lib/libtree-sitter-toml.so"

echo ""
echo "If Ruby cannot find libraries at runtime, you may need to export:"
echo "  export LD_LIBRARY_PATH=/usr/local/lib:/usr/lib64:/usr/lib"
