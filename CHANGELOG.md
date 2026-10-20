# Changelog

What's new in Archeion: the Lyceum Editions (the curated, generated texts Lyceum and Lyceum Study show) and the
pipeline that makes and ships them. Releases of the data are on GitHub (v* for Lyceum's databases, preload-v* for
Lyceum Study). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are release
dates.

## [Unreleased]

## [2026-10-20]

### Added

- The complete Epistle to the Romans: 432 passages (1.1-16.27), up from chapter 1 (32).
- The complete Crito: 139 passages (43-54), up from 43-44 (31).

### Changed

- Lyceum Study (formerly Aristos) is named as such throughout.

### Internal

- `kai run sync-lyceum` brings Lyceum's databases up to date with every work on the site (the configs in
  scripts/lyceum-imports/): a dry run lists Archeion's and Lyceum's passages per work; `--apply` imports only the
  works that changed, after one backup, and records them in the website's data/lyceum-editions.json.
- `kai workflow release-staging`: sync, deploy Lyceum's data to staging, and stage Lyceum Study with the same data
  (scripts/study.roc packs, pins and deploys its preload); then draft the changelogs. Nothing is published.
- `kai workflow release-production`: date the changelogs, then promote: Lyceum's data to production with its
  Archeion release, and Lyceum Study's pinned preload published and deployed.
- `scripts/changelog.roc` drafts and releases the changelogs of Archeion, Lyceum and Lyceum Study.

## [2026-10-13]

- What Lyceum production serves: the data of release v2026.10.05-staging. Earlier changes are in the git history
  and the GitHub releases.
