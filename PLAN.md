# PLAN.md

## Goal
Integrate the shared Comment AST & Merge capability into `toml-merge` so TOML tables, keys, and file-level sections preserve comments during merges without producing invalid TOML.

`psych-merge` is the reference for shared comment behavior, but `toml-merge` must keep TOML-valid output across parser/backend differences.

## Current Status
- `toml-merge` is a high-value config target because TOML comments are common and usually structure the file for humans.
- The gem has the standard merge-gem layout and is expected to normalize tables, pairs, and section ordering.
- Comment support likely needs to bridge parser/backend differences rather than assume one native ownership model.
- The main constraint is preserving comments while staying TOML-valid across equivalent representations.

## Integration Strategy
- Expose shared comment capability from file analysis and node wrappers.
- Normalize comment ownership around:
  - document prelude/postlude
  - table headers
  - key/value pairs
  - blank-line-separated comment blocks between sections
- Prefer native parser ownership when reliable; otherwise fall back to source-augmented tracking.
- Reuse the `psych-merge` behaviors for matched-node fallback and removed-node comment preservation.

## First Slices
1. Add shared comment capability plumbing to file analysis and wrapped nodes.
2. Preserve top-of-file and trailing comments around table merges.
3. Preserve leading and inline comments for matched keys when template content wins.
4. Preserve comments for removed destination-only keys or tables when removal is enabled.
5. Expand arrays-of-tables and adjacent table comment-block scenarios.

## First Files To Inspect
- `lib/toml/merge/file_analysis.rb`
- `lib/toml/merge/node_wrapper.rb`
- `lib/toml/merge/smart_merger.rb`
- `lib/toml/merge/conflict_resolver.rb`
- `lib/toml/merge/emitter.rb`
- any normalizers or refiners under `lib/toml/merge/`

## Tests To Add First
- file analysis specs for comment regions
- emitter specs for leading / inline / promoted comment emission
- smart merger specs for table and key comment preservation
- conflict resolver specs for removed-node behavior
- reproducible fixtures for comment-heavy TOML tables and arrays of tables

## Risks
- Different TOML backends may report positions differently.
- Dotted keys, inline tables, and arrays of tables can make ownership ambiguous.
- Equivalent TOML structures must still emit valid, stable TOML.
- Comments between adjacent tables can be hard to assign consistently.

## Success Criteria
- Shared comment capability is available through the analysis layer.
- Table, key, and file-level comments survive common merges.
- Removed destination-only keys/tables can preserve comments safely.
- Arrays of tables and multi-section files keep stable comment association.
- Reproducible fixtures capture the highest-risk TOML comment patterns.

## Rollout Phase
- Phase 1 target.
- Recommended after `prism-merge` because it is high-value config work but may need more backend normalization than YAML or Ruby.

## Execution Backlog

### Slice 1 — Shared capability + file/table boundaries
- Add `comment_capability`, `comment_augmenter`, and normalized attachments to file analysis.
- Preserve document prelude/postlude comments and table-leading comment blocks.
- Add focused specs for root comments, table comments, and comment-only files.

### Slice 2 — Matched and removed keys / tables
- Preserve destination leading and inline comments when matched template-preferred keys win.
- Preserve comments for removed destination-only keys and tables when removal is enabled.
- Add resolver/smart-merger regressions for adjacent tables and blank-line-separated comment blocks.

### Slice 3 — Arrays of tables + fixtures
- Extend the same ownership rules to arrays of tables, dotted keys, and mixed section layouts.
- Add reproducible fixtures for the highest-risk TOML comment scenarios.
- Re-check backend parity once the focused cases are stable.

## Dependencies / Resume Notes
- Start in `lib/toml/merge/file_analysis.rb` and `lib/toml/merge/node_wrapper.rb`.
- Use `psych-merge` as the shared-behavior reference, but keep TOML-specific validity constraints primary.
- Be alert for backend-specific range differences before broadening coverage.

## Exit Gate For This Plan
- File-level, table-level, and key-level comments survive common TOML merges.
- Arrays of tables and adjacent sections keep stable comment ownership without invalid TOML output.
