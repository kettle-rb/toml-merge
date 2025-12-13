#!/bin/sh
set -e

# Install basic development dependencies for Ruby & JRuby projects
apt-get update -y
apt-get install -y direnv default-jdk git

# Support for PostgreSQL (commented out by default)
# apt-get install -y postgresql libpq-dev

# Run the shared tree-sitter setup script (without sudo since we're already root in devcontainer)
/workspaces/toml-merge/.github/scripts/ubuntu/setup-tree-sitter.sh

# Adds the direnv setup script to ~/.bashrc file (at the end)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
