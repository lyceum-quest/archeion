# Archeion

This repository stores data outputs and data documentation for [lyceum.quest](https://lyceum.quest), a digital library and reader for Ancient Greek.

It is organized as a small set of data subprojects. The top-level README gives the map; each subdirectory README documents that subproject in more detail.

## Subprojects

| Path | Purpose | Start here |
|---|---|---|
| [`db/`](db/) | SQLite database documentation for reader, corpus, morphology, dictionary, and learner-state databases. The large `.db` artifacts are release assets, not normal git-tracked files. | [`db/README.md`](db/README.md) |
| [`conllu/`](conllu/) | Ancient Greek CoNLL-U dependency treebank data: the Lyceum editions served on lyceum.quest (`conllu/lyceum/`), plus Aesop fables, Aristotle's *Poetics*, and Xenophon's *Anabasis* Book 1 used by the CoNLL-U visualizer. | [`conllu/README.md`](conllu/README.md) |
| [`conllu/generated/`](conllu/generated/) | Every generated work (`<work>-<model>/`): glosses, translations, passages, and generation costs. | [`PIPELINE.md`](PIPELINE.md) |
| [`scripts/`](scripts/), [`data/oga/`](data/oga/) | The pipeline (Roc, run through `Kaifile.roc`) and the OGA citation data it uses. [`experiments/`](experiments/) and [`RESEARCH.md`](RESEARCH.md) record how prompts and models were chosen. | [`PIPELINE.md`](PIPELINE.md) |
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

Archeion holds the whole pipeline, from pinned source corpora to releases; see [`PIPELINE.md`](PIPELINE.md). Generated works live in [`conllu/generated/`](conllu/generated/) (`kai run generate`). From there:

- **Aristos** pins a `preload-vYYYY.MM.DD` release (`aristos-preload.tar.zst`: every generated work with its passages and lemma index), built by `kai workflow preload-release`.
- **Lyceum** is deployed databases imported here (`kai run import-lyceum`, `kai run deploy-lyceum-data`); `kai workflow release-lyceum` then publishes exactly what production serves as a `vYYYY.MM.DD` release, copying each imported work into [`conllu/lyceum/`](conllu/lyceum/).

Learner data (`users.db`) is never published.

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
