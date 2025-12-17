# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- Initial release
- Added support for pure Ruby TOML parsing via tree_haver v3 Citrus backend with toml-rb
  - Automatically registers both tree-sitter-toml (native, fast) and toml-rb (pure Ruby) grammars
  - TreeHaver auto-selects best available backend (tree-sitter preferred, Citrus fallback)
  - Enables TOML parsing on platforms without native library support
  - Can force Citrus backend via `TREE_HAVER_BACKEND=citrus` environment variable
- Added graceful error handling when neither tree-sitter-toml nor toml-rb are available

### Changed

### Deprecated

### Removed

### Fixed

### Security

[Unreleased]: https://github.com/kettle-rb/toml-merge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kettle-rb/toml-merge/compare/772a5f5802ce518f2e2c83a561eb583ed634bac4...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/toml-merge/tags/v1.0.0
