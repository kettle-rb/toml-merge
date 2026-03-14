# PLAN.md

## Goal
Integrate the shared Comment AST & Merge capability into `toml-merge` so TOML tables, keys, and file-level sections preserve comments during merges without producing invalid TOML.

`psych-merge` is the reference for shared comment behavior, but `toml-merge` must keep TOML-valid output across parser/backend differences.

## Current Status
- `toml-merge` is a high-value config target because TOML comments are common and usually structure the file for humans.
- The gem has the standard merge-gem layout and is expected to normalize tables, pairs, and section ordering.
- Comment support likely needs to bridge parser/backend differences rather than assume one native ownership model.
- Slice 1 analysis and wrapper plumbing exists: shared comment capability surfaces are present in file analysis and wrapped nodes, with native tree-sitter comment support plus source-scanned fallback for non-native backends.
- 2026-03-12 follow-up work cleaned up autoload-boundary drift: explicit `Ast::Merge::Comment` subfile requires were removed and comment lookup is being consolidated behind `Toml::Merge::CommentTracker`.
- The overlap between wrapper-local `leading_comments` / `inline_comment` lookup and shared tracked comment entries is now being reduced, and focused validation passed on 2026-03-12 after tightening augmenter owner ranges for postlude detection.
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

## Latest `ast-merge` Comment Logic Checklist (2026-03-12)
- [x] Shared capability plumbing: `comment_capability`, `comment_augmenter`, normalized region/attachment access
- [x] Document boundary ownership: prelude/postlude analysis ownership, table-leading/header emission, and comment-only-file merger/emitter parity are in place
- [x] Matched-node fallback: preserve destination leading/inline comments when template content wins
- [x] Removed-node preservation: keep/promote destination comments when removal is enabled
- [x] Recursive/fixture parity: adjacent table blocks and matched arrays-of-tables are covered in both focused regressions and reproducible fixtures

Current parity status: aligned on the current rollout scope; boundary/comment-only behavior, matched-key fallback, removed-node preservation, adjacent-table handling, matched arrays-of-tables behavior, and reproducible fixture promotion are all now verified against the local sibling shared comment code.
Next execution target: no immediate TOML comment-rollout slice remains; return only if a new dotted-key, mixed-layout, or backend-specific comment ownership escape is reproduced.

## Execution Backlog

## Progress
- 2026-03-12: Slice 3 reproducible fixture promotion completed.
- Added `spec/integration/reproducible_merge_spec.rb` plus reproducible fixtures for adjacent matched-table and matched array-of-tables destination-doc preservation under template preference.
- Revalidated the new fixture harness, the focused TOML comment suite, and the full `toml-merge` suite against the local sibling `ast-merge` / `tree_haver` code; all are green aside from the existing 2 pending Parslet parse-error examples.
- 2026-03-12: Recursive parity follow-up advanced.
- Extended matched-table handling so template-preferred recursive table merges can fall back to destination leading docs and header inline comments when the template lacks them, preserving adjacent-table documentation without regressing template-owned comments.
- Added focused `smart_merger_spec` and `conflict_resolver_spec` regressions for adjacent matched tables and matched arrays-of-tables with destination docs under template preference; the full `toml-merge` suite remains green afterward.
- 2026-03-12: Slice 2 removed-node preservation completed.
- Added `remove_template_missing_nodes` plumbing to `Toml::Merge::SmartMerger` / `ConflictResolver` and taught the resolver to preserve/promote comments for removed destination-only keys, extra duplicate nodes, and removed tables without keeping their structural TOML bodies.
- Added focused `smart_merger_spec` and `conflict_resolver_spec` regressions for removed keys and removed tables, then revalidated the focused TOML comment specs and the full `toml-merge` suite against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 2 matched-key fallback completed.
- Taught `Toml::Merge::ConflictResolver` to preserve destination leading-comment regions, interstitial blank lines, and inline comment text when template-preferred matched keys win, while still honoring template-owned inline comments when they already exist.
- Added focused `smart_merger_spec` and `conflict_resolver_spec` regressions for template-preferred matched key merges with destination docs/inline notes and verified the full `toml-merge` suite against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 1 merger/emitter boundary parity completed.
- Taught `Toml::Merge::ConflictResolver` / `Emitter` to preserve selected-side table-leading comments, inline table-header comments, root postlude spacing, and comment-only-document output instead of dropping those regions during recursive table merges.
- Switched recursive table merging to use `mergeable_children` rather than raw parser children so shared comment emission can recurse structurally without duplicating table headers.
- Added focused `smart_merger_spec` coverage for destination table-leading/postlude preservation, template-preferred header comment retention, and comment-only destinations; the full `toml-merge` suite now passes with those regressions in place.
- 2026-03-12: Focused revalidation completed after the autoload-boundary cleanup.
- Revalidated `spec/toml/merge/smart_merger_spec.rb`, `spec/toml/merge/file_analysis_spec.rb`, and `spec/toml/merge/node_wrapper_spec.rb`, plus the full `toml-merge` suite, against the local sibling `ast-merge` / `tree_haver` code.
- Tightened TOML augmenter owner-range normalization so table wrappers stop claiming EOF-spanning postlude comments; shared `postlude_region` inference now reflects structural TOML ownership instead of raw wrapper end lines.
- Relaxed the autoload-boundary spec so it proves TOML stays on the `Ast::Merge::Comment` namespace boundary whether helper classes are still pending autoload or were already loaded earlier in the suite.
- 2026-03-12: Status sync after the autoload audit.
- Removed explicit `require "ast/merge/comment..."` usage from the TOML comment-integration path so `ast-merge` autoload remains the boundary.
- Added `Toml::Merge::CommentTracker` and started consolidating shared comment lookup so analysis-layer helpers and wrapped nodes stop carrying overlapping association logic.
- Added/updated focused spec coverage for autoload exposure and tracker-derived wrapper associations; the clean rerun passed later on 2026-03-12.
- 2026-03-11: Phase 1 / Slice 1 started.
- Added shared comment capability plumbing in `Toml::Merge::FileAnalysis` (`comment_capability`, `comment_nodes`, `comment_node_at`, `comment_region_for_range`, `comment_attachment_for`, `comment_augmenter`) with `Ast::Merge::Comment::*` integration.
- Added backend-aware capability reporting so tree-sitter-backed parses report native-partial support while parslet-backed parses fall back to source-augmented comment tracking.
- Extended `Toml::Merge::NodeWrapper` to retain leading and inline comment associations from tracked comment entries.
- Added focused `file_analysis_spec` and `node_wrapper_spec` coverage for shared capability exposure, prelude/postlude region discovery, native-vs-source fallback, and wrapped-node comment associations.
- Pre-refactor focused coverage existed for the Slice 1 path; after the 2026-03-12 tracker/autoload cleanup, focused revalidation passed and merger-path preservation plus comment-only file emission remain the next feature gap.

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
- Resume by proving `CommentTracker`-based lookup is stable before doing more merger/emitter work.
- When validating against the latest shared comment rollout from sibling checkouts, prepend the local `ast-merge/lib` and `tree_haver/lib` via `RUBYLIB` so the suite exercises the in-workspace shared comment classes rather than the currently installed released gems.

## Exit Gate For This Plan
- File-level, table-level, and key-level comments survive common TOML merges.
- Arrays of tables and adjacent sections keep stable comment ownership without invalid TOML output.
