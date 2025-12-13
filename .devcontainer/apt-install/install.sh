#!/bin/sh
apt-get update -y

# Basic, commonly needed, dependencies of Ruby & JRuby projects
apt-get install -y direnv default-jdk git zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libxml2-dev libxslt1-dev libcurl4-openssl-dev software-properties-common libffi-dev

# Support for PostgreSQL
# apt-get install -y postgresql libpq-dev

# Support for tree sitters
apt-get install -y pkg-config libtree-sitter-dev tree-sitter-cli

# Support for specific tree sitter syntaxes
apt-get install -y wget gcc g++ make
cd /tmp
wget https://github.com/tree-sitter/tree-sitter-toml/archive/refs/heads/master.zip
unzip master.zip
cd tree-sitter-toml-master
gcc -fPIC -I./src -c src/parser.c -o parser.o
gcc -fPIC -I./src -c src/scanner.c -o scanner.o
gcc -shared -o libtree-sitter-toml.so parser.o scanner.o
cp libtree-sitter-toml.so /usr/local/lib/
ldconfig

# Adds the direnv setup script to ~/.bashrc file (at the end)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
