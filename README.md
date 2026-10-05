# Archeion

This repository stores data outputs and data documentation for [lyceum.quest](https://lyceum.quest), a digital library and reader for Ancient Greek.

It is organized as a small set of data subprojects. The top-level README gives the map; each subdirectory README documents that subproject in more detail.

## Subprojects

| Path | Purpose | Start here |
|---|---|---|
| [`db/`](db/) | SQLite database documentation for reader, corpus, morphology, dictionary, and learner-state databases. The large `.db` artifacts are release assets, not normal git-tracked files. | [`db/README.md`](db/README.md) |
| [`conllu/`](conllu/) | Ancient Greek CoNLL-U dependency treebank data: the Lyceum editions served on lyceum.quest (`conllu/lyceum/`), plus Aesop fables, Aristotle's *Poetics*, and Xenophon's *Anabasis* Book 1 used by the CoNLL-U visualizer. | [`conllu/README.md`](conllu/README.md) |
| [`releases/`](releases/) | One manifest per release: database checksums, the Lyceum editions included, and the source commits they came from. | [`releases/`](releases/) |
| [`orchestrator/`](orchestrator/) | Archived per-text workspaces from the experimental (now deprecated) orchestrator pipeline. These are historical snapshots with raw sources, structured text, interlinear output, and QA artifacts where present. See discussion of the pipeline [here](https://blu.cx/posts/articles/2026-03-31-lyceum-pipeline/). | [`orchestrator/README.md`](orchestrator/README.md) |

## Release assets

Runtime database files are distributed through GitHub Releases rather than checked into this repository:

- `texts.db` — reader text library and alignments
- `editions.db` — curated Lyceum editions and source tracking
- `morph.db` — Greek morphology lookup data
- `lsj.db` — LSJ dictionary data

Releases made by `publish-archeion` carry all four databases, compressed with zstd (`zstd -d texts.db.zst`), with `SHA256SUMS.txt` and a `manifest.json` listing each database's checksum before compression. Download current artifacts from the [latest release](https://github.com/lyceum-quest/archeion/releases/latest). See [`db/`](db/) for schema notes, inventories, and regeneration policy.

## How data gets here

Archeion publishes what lyceum.quest serves. Its content comes from the [Aristos](https://github.com/lyceum-quest/aristos) pipeline, in four separate steps run from an Aristos checkout:

1. **Generate** — `kai run generate` glosses and translates a work into `conllu/generated/<work>-<model>/` (`output.conllu`, `units.jsonl`, `config.json`).
2. **Import** — `kai run lyceum-import-config` and `kai run import-lyceum` load the work's passages into the website's `texts.db` and `editions.db`.
3. **Deploy** — `kai run deploy-lyceum-data` (staging) or `deploy-lyceum-data-prod` installs those databases on a Lyceum host.
4. **Publish** — `kai run publish-archeion` checks that production serves exactly the local `texts.db`, `editions.db`, `morph.db`, and `lsj.db`, copies every imported work into [`conllu/lyceum/`](conllu/lyceum/) (only as far as it is imported), writes the release manifest to `releases/`, commits, and tags `vYYYY.MM.DD`. `push-archeion` pushes the commit and tag; `release-archeion-github` uploads the compressed databases as the GitHub release.

`kai workflow release-lyceum` runs the production deploy and all of step 4 together, so a release always matches the site at that moment. See Aristos's `DEPLOYMENT.md` for settings. Learner data (`users.db`) is never published.

## Usage

For tooling that expects this repository on disk, set:

```bash
export LYCEUM_TEXTS_DIR=/path/to/archeion
```

Then consult the relevant subproject README for file layout, provenance, and maintenance rules.

## Versioning

Releases use Calendar Versioning:

```text
vYYYY.MM.DD
```

A second release on the same day appends a counter (`vYYYY.MM.DD.2`). Each release tags the commit holding its CoNLL-U snapshot and manifest.
