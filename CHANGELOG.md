# Changelog

What's new in Archeion: the Lyceum Editions (the curated, generated texts Lyceum and Lyceum Study show) and the
pipeline that makes and ships them. Releases of the data are on GitHub (v* for Lyceum's databases, preload-v* for
Lyceum Study). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are release
dates.

## [Unreleased]

### Added

- The Gospel of Luke continues through chapter 2: 132 passages (1.1-2.52), up from chapter 1 (80). Chapter 2 has
  prose translations and word glosses, but no literal translations yet.

### Internal

- Luke 2 was generated with apo 0.1.0 (claude-sonnet-5, through the Claude Code login) and added with
  `kai run adopt-apo`, a stopgap that continues a generated work with apo's output for its later sentences. Each apo
  session's output is kept in the work's `apo/<first token>/`.
- `lyceum-import-config` leaves out an empty literal translation, which Lyceum reads as none.
- Archeion and Lyceum Study build with Kai 0.0.10; `kai run apo` passes its options to apo.
- GitHub releases use the repository owner's token, a failed `gh` call no longer prints it, and publishing a preload
  release that already exists is skipped.
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
