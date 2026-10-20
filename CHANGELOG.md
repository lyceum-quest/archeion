# Changelog

What's new in Archeion: the Lyceum Editions (the curated, generated texts Lyceum and Lyceum Study show) and the
pipeline that makes and ships them. Releases of the data are on GitHub (v* for Lyceum's databases, preload-v* for
Lyceum Study). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are release
dates.

## [Unreleased]

<!-- release draft (Archeion's changelog.roc): what changed since release-2026.10.13. Describe it in the entries below, in reader language (Internal for the rest), then delete this comment.
Commits:
- bcdc67a feat: changelogs for Archeion, Lyceum and Lyceum Study, drafted and released by the release workflows
- f10e2e6 fix: a sync or stage with nothing new does nothing
- e8ed432 feat: kai workflow release-staging and release-production, for Lyceum and Lyceum Study together
- 1e5ee36 feat: kai run sync-lyceum brings Lyceum up to date with every work on the site
- 922dcff feat: complete Romans and Crito
- d5a737b feat: release the CoNLL-U visualizer's treebanks from Archeion
- d8a00c1 fix: check release checksums from the release directory
- c5538fd build: run the pipeline from Archeion
- a346550 docs: deploy Aristos to staging at study.internal.blu.cx
- 5be1be3 feat: Today and Words views, study tweaks, and Archeion publish/push scripts
- cc4dbd0 fix: import Lyceum editions without Aristos names, and words OGA tags as punctuation
- ed4a523 fix: deploy Lyceum data to hosts without the admin panel
- 5b6549d feat: import Aristos passages into Lyceum, one per verse or section
- 865b27e feat: add Lyceum import configs for 2 John and 3 John
- 4e108ca build: port the Kaifile to Kaifile.roc
- 0ff1f97 feat: deploy Lyceum staging over the tailnet
- 4706bb9 feat: generate Lyceum import configs from OGA citations
- b2d2d4d feat: locate the Lyceum website through LYCEUM_WEBSITE_DIR
- a630600 feat: add 2 John and 3 John
- a302fdf fix: read subscription costs that Dec cannot parse
- d10ebb2 feat: add 2 Peter and Crito 43–44
- be374cb feat: group dialogues into speaker turns with a page and § picker
- 4ce15a7 feat: add a subscription backend to the generation pipeline
- 84f80e2 feat: add Romans chapter 1
- fa78583 fix: keep gloss style out of passage literal translations
- db99f15 feat: study and read works by canonical citation
- f810232 fix: leave OGA placeholder rows out of preload token counts
- 46624b9 refactor: drop hand-written source blocks from work configs
- d311475 feat: attach generated citations to the preload manifest
- d0a6cac feat: derive work citations from OGA's bibliographic table
- 00ffd9c feat: add generated First Epistle of Peter
- 790e9dd chore: adopt the shared base prompt for continuing Luke
- 7c6631b fix: capitalize God and Lord in Luke chapter 1 glosses
- 92d9e7c feat: build the preload from every generated work
- d24606c feat: add generated Luke chapter 1 from Opera Graeca Adnotata
- f968dbf feat: generate any work through one resumable Kai task
- 181fec3 refactor: move Meditations output to a per-work folder
- 45ced34 feat: preserve imported sentence boundaries alongside canonical passages
- ac76d10 feat: deploy Lyceum content with staged verification and rollback
- f9cf32c feat: add generated Meditations Book 1 and chapter mappings
- 547ab3a feat: replace Lyceum editions with mapped corpus passages
- 8749f94 feat: resume corpus generation with real-token-only gloss requests
- 50efc01 feat: import verse-aligned conllu into lyceum
- 9680edc refactor: keep sonnet as the corpus generation pipeline
- a1499e3 refactor: move sonnet results into generated corpora
- 8899e68 docs: qualify claude calibration results
- 96afcbd docs: record best claude experiment result
- 395a259 docs: preserve tuned structured claude result
- 4eab9ae docs: preserve first structured claude result
- c641bc0 refactor: use structured semantic responses
- e361b33 wip claude
- 7e7647b glm 5.3 fail
- 40a32e7 chore: select deepseek pro experiment config
- a6dd91b docs: preserve deepseek pro experiment results
- a5863c5 docs: preserve deepseek flash experiment results
- 77e62b7 wip
- 9d4e54b feat: make conllu pipeline resumable
- ddb24f3 genesis
- ab3deca prepare genesis sample
- 8c068a5 wip
- bba977e fixes
- 770593c modify improve and audit
- c891df9 improve roc
- b43c93d reorg
- 0741c3e update kaifile simpler
- 90152a0 rename run to prep
- 2355c23 audit.roc
- 7842173 initial glosses
- f9415d3 create roc file to use OGA conllu as basis for prose and literal translation
- ec9d10c update prep.roc
- e14d81b wip
- 8d549d7 updated deepseek prompt, better results
- 8071e02 jev-validate
- 7d6fbf8 new results with batching
- 7f3f728 Batch calls
- d9475b7 init deepseek prep script
- 66762f5 config smoke again
- fecf381 better config setup
- df65a18 roc script for deepseek-jev
- dcc75dd update
- 78223a6 docs: plan deterministic DeepSeek Jev experiment
- 5ec329c wip setup
- d20140d jev result 1 smoke
- 3e4ffac wip
- 939ab0c experiment 3 setup with jev
- 24b4c3d Setup OGA deepseek experiment
- 7cbd684 disable reasoning for deepseek flash v4
- 639e969 Deepseek flash non thinking results
- f2ce131 wip exp 2
- 52191e3 Placeholder conllu experimental setup
- ffec023 update
- dea57de Remove outdated experiments
- 5638032 New experiment runs
- 3ce10bd Update to use latest roc compiler
- c4b33b4 closed model experiment
- 24584d7 qwen 397
- 323b228 qwen experiment 2
- 3b54e21 checkpoint
- 5d191b8 successful deepseek
- d1fddc0 initial experiment
- 784a29c feat: add recursive conllu linter
- 749d487 feat: preload raw CoNLL-U corpora
- f8e5a35 feat: import Anabasis fixture with Roc
- 4d3f26a feat: add full Lyceum Anabasis comparison corpus
- 48c58f5 fix: copy Anabasis sentence with upstream provenance
- 3f60cf3 feat: add Anabasis opening sentence corpus fixture
-->

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
