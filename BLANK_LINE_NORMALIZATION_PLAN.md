# Blank Line Normalization Plan for `toml-merge`

_Date: 2026-03-19_

## Role in the family refactor

`toml-merge` is a structured config-file adopter for the shared blank-line normalization effort.

The main goal is to make spacing around keys, tables, promoted comments, and preserved postludes use the same shared layout rules as the rest of the family.

## Current evidence files

Implementation files:

- `lib/toml/merge/smart_merger.rb`
- `lib/toml/merge/conflict_resolver.rb`
- `lib/toml/merge/file_analysis.rb`

Relevant specs:

- `spec/toml/merge/smart_merger_spec.rb`
- `spec/toml/merge/conflict_resolver_spec.rb`
- `spec/toml/merge/removal_mode_compliance_spec.rb`

## Current pressure points

Spacing matters in TOML around:

- leading comment blocks for keys and tables
- promoted inline comments after removed keys/tables
- preserved document postludes
- nested table removal and adjacency changes

## Migration targets

- move blank-line preservation onto shared `ast-merge` layout concepts
- reduce repo-local string manipulation for separator normalization
- keep table/key readability stable under repeated merges

## Workstreams

- map existing table/key/postlude gap behavior
- migrate top-level separator handling first
- migrate nested table removal-mode spacing second
- validate no extra blank-line accumulation or swallowing occurs

## Exit criteria

- TOML spacing around comments, keys, and tables follows the shared layout contract
- recursive/top-level behavior remains consistent where supported
- focused TOML regressions remain green with fewer bespoke spacing fixes
