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
#   --build: Build and install the tree-sitter C runtime from source when distro packages are missing (optional)

SUDO=""
INSTALL_CLI=false
BUILD_FROM_SOURCE=false

for arg in "$@"; do
  case $arg in
    --sudo)
      SUDO="sudo"
      ;;
    --cli)
      INSTALL_CLI=true
      ;;
    --build)
      BUILD_FROM_SOURCE=true
      ;;
  esac
done

have_cmd() { command -v "$1" >/dev/null 2>&1; }

have_tree_sitter() {
  # Check common header and library locations for an installed tree-sitter
  [ -f /usr/include/tree-sitter/api.h ] && return 0
  [ -f /usr/local/include/tree-sitter/api.h ] && return 0
  [ -f /usr/local/include/tree-sitter/lib/include/api.h ] && return 0
  ldconfig -p 2>/dev/null | grep -q libtree-sitter && return 0 || return 1
}

install_tree_sitter_from_source() {
  echo "[universal-blue] Attempting to build and install tree-sitter from source..."
  tmpdir=$(mktemp -d /tmp/tree-sitter-src-XXXX)
  trap 'rm -rf "$tmpdir"' EXIT
  git clone --depth 1 https://github.com/tree-sitter/tree-sitter.git "$tmpdir" || return 1
  pushd "$tmpdir" >/dev/null || return 1
  if ! make; then
    echo "[universal-blue] ERROR: 'make' failed while building tree-sitter" >&2
    popd >/dev/null
    return 1
  fi

  # Install headers
  $SUDO mkdir -p /usr/local/include/tree-sitter
  $SUDO cp -r lib/include/* /usr/local/include/tree-sitter/ || true

  # Install library artifacts
  $SUDO cp -a lib/libtree-sitter.* /usr/local/lib/ 2>/dev/null || true
  if have_cmd ldconfig; then
    $SUDO ldconfig || true
  fi

  popd >/dev/null
  echo "[universal-blue] tree-sitter built and installed to /usr/local (headers + libs)."
  return 0
}

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
  )

  echo "[universal-blue] Layering packages via rpm-ostree: ${PKGS[*]}"
  layered_any=false

  for pkg in "${PKGS[@]}"; do
    echo "[universal-blue] Attempting to layer package: ${pkg}"
    out=$($SUDO rpm-ostree install -y "$pkg" 2>&1) || status=$?
    if [ "${status:-0}" -eq 0 ]; then
      layered_any=true
      echo "[universal-blue] Layered: ${pkg}"
      unset status out
      continue
    fi

    # Handle a set of common harmless outputs and treat them as non-fatal
        DNF_PKGS=(
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
        )
        if [ "$BUILD_FROM_SOURCE" = false ]; then
          DNF_PKGS+=(libtree-sitter libtree-sitter-devel)
        else
          echo "[universal-blue] --build specified; will skip distro 'libtree-sitter' / 'libtree-sitter-devel' packages and build from source instead."
        fi

        $SUDO dnf install -y "${DNF_PKGS[@]}"
    # Unexpected failure - surface and abort
    echo "[universal-blue] ERROR: Failed to layer package '${pkg}':"
    echo "$out"
    exit 1
  done

  # If the user requested a source build, skip the distro tree-sitter-devel package
  if [ "$BUILD_FROM_SOURCE" = false ]; then
    brew install tree-sitter
    brew install tree-sitter-cli
    brew install mise
    mise use lua
    luarocks install tree-sitter-bash
    luarocks install tree-sitter-json
    luarocks install tree-sitter-jsonc
    luarocks install tree-sitter-toml
  else
    echo "[universal-blue] --build specified; will skip distro 'libtree-sitter' / 'libtree-sitter-devel' and build from source instead."
  fi

  echo ""
  if [ "$layered_any" = true ]; then
    echo "[universal-blue] Packages were layered; a reboot is required before building."
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
    echo "[universal-blue] No new packages were layered; continuing with build/install steps."
  fi
else
  echo "[universal-blue] rpm-ostree not detected. Assuming classic Fedora or containerized environment."
  if have_cmd dnf; then
    if [ "$BUILD_FROM_SOURCE" = false ]; then
      DNF_PKGS+=(libtree-sitter libtree-sitter-devel libtree-sitter-bash libtree-sitter-json libtree-sitter-toml)
    else
      echo "[universal-blue] --build specified; will skip distro 'libtree-sitter' / 'libtree-sitter-devel' packages and build from source instead."
    fi
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
      libffi-devel
  else
    echo "[universal-blue] ERROR: Neither rpm-ostree nor dnf is available."
    echo "Please install required packages using your environment's package manager, then re-run."
    exit 1
  fi
fi

# Ensure tree-sitter is available (headers/libs); if not, attempt to build from source
if ! have_tree_sitter; then
  if [ "$BUILD_FROM_SOURCE" = true ]; then
    echo "[universal-blue] tree-sitter not found in system paths; attempting to build from source as requested (--build)."
    if ! install_tree_sitter_from_source; then
      echo "[universal-blue] ERROR: Failed to provide tree-sitter runtime/library. Aborting." >&2
      exit 1
    fi
  else
    echo "[universal-blue] ERROR: tree-sitter runtime (headers/libs) not found."
    echo "Install the appropriate distro package (e.g., libtree-sitter, libtree-sitter-devel) or re-run this script with --build to compile from source."
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
echo "[universal-blue] tree-sitter setup complete!"
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
