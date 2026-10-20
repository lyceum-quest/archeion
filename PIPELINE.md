# Data pipeline

Archeion holds the whole path from source corpora to what the apps serve. The apps generate no data:

- **Lyceum Study** (the study app) pins a preload release in its `preload.lock.json` and fetches it.
- **conllu-viz** (the CoNLL-U visualizer) pins a `conllu-viz-v*` release in its `data.lock.json`.
- **Lyceum** (the reader at lyceum.quest) is deployed the databases imported here and published as `v*` releases.

Tasks run with `kai run <task>` (or `kai workflow <workflow>`); see `Kaifile.roc`. Settings come from the
environment or a git-ignored `.env` (copy `.env.example`).

## Generation

`kai run generate -- <work> <config.json> <passage-count|all>` glosses sentences and translates canonical passages
(verses or sections, from OGA's citation layer in `data/oga/refs/`) into `conllu/generated/<work>-<model>/`:
`output.conllu`, `units.jsonl` (passages with token IDs and prose and literal translations), `config.json` (model,
source, prompts), and `costs.tsv`. It resumes from its checkpoints; missing work makes model calls. Work configs are
in `scripts/generate/works/`. `RESEARCH.md` and `experiments/` record how the prompts and models were chosen.

## Lyceum Study preload

The preload is every generated work as Lyceum Study loads it: `corpora.json` (version 1), `corpora/<work>.conllu`,
`corpora/<work>.units.json`, and `lemmas.json`. `kai run preload` builds it into `preload/` for inspection.

```sh
kai workflow preload-release                # check the tools, build from the committed works, tag preload-vYYYY.MM.DD
git push origin preload-vYYYY.MM.DD
ARCHEION_GITHUB_RELEASE=1 kai run release-preload-github
```

The archive `aristos-preload.tar.zst` is reproducible (sorted entries, zero mtimes and owners, `zstd -19`), so the
same commit always gives the same SHA-256. Pin it in Lyceum Study by setting `preload.lock.json` to the release's URL and
checksum.

## CoNLL-U visualizer preload

The visualizer at conllu.lyceum.quest preloads the treebanks listed in `conllu/conllu-viz.json` (its
`conllu-files.json`; paths under `/preload/` are paths under `conllu/`).

```sh
kai run release-conllu-viz                  # tag conllu-viz-vYYYY.MM.DD
git push origin conllu-viz-vYYYY.MM.DD
ARCHEION_GITHUB_RELEASE=1 kai run release-conllu-viz-github
```

The archive `conllu-viz-preload.tar.gz` is reproducible like the Lyceum Study one; conllu-viz pins it in `data.lock.json`.

## Lyceum reader data

Generated works are imported into the Lyceum website's `data/texts.db` and `data/editions.db` and deployed to its
hosts. Every task that touches the website finds its checkout through `LYCEUM_WEBSITE_DIR`; nothing falls back to a
guessed path.

```sh
cp .env.example .env            # then set LYCEUM_WEBSITE_DIR

# Write a generated work's passages (units.jsonl, one Lyceum passage per verse or section) to /tmp and its import
# config to scripts/lyceum-imports/.
kai run lyceum-import-config -- conllu/generated/romans-claude-sonnet-5
# A work whose Lyceum editions predate these passages is replaced in place instead:
kai run lyceum-import-config -- conllu/generated/meditations-claude-sonnet-5 \
  --replace urn:cts:greekLit:tlg0562.tlg001.workspace-grc1 urn:cts:greekLit:tlg0562.tlg001.workspace-grc1-gen-eng1

# Write the SQL only, then apply it (backs up both databases first).
LYCEUM_IMPORT_CONFIG=scripts/lyceum-imports/romans-claude-sonnet-5.json kai run import-lyceum
LYCEUM_IMPORT_CONFIG=scripts/lyceum-imports/romans-claude-sonnet-5.json LYCEUM_IMPORT_APPLY=1 kai run import-lyceum

kai run deploy-lyceum-data      # staging, over the tailnet
LYCEUM_DEPLOY_PRODUCTION=1 kai run deploy-lyceum-data-prod
```

Applying needs the website's full `data/texts.db`, which is not in its Git repository, and the work and its author
must already be in its catalog. Configs in `scripts/lyceum-imports/` add an `aristos-<model>` edition;
`scripts/lyceum-replace.example.json` instead replaces two existing editions wholesale. A re-import replaces the
passages it names and keeps the rest. Deploying connects with SSH as root (it stops and starts the `lyceum` service
and installs the databases into `/var/lib/lyceum/data` owned by `lyceum`) to `LYCEUM_STAGING_HOST` (default
`lyceum-staging`, the tailnet name) or `LYCEUM_PROD_HOST` (default `lyceum-prod`), then checks `<url>/health`.
Staging needs no public domain.

## Lyceum releases

`publish-archeion` checks that production serves exactly the website's local `texts.db`, `editions.db`, `morph.db`,
and `lsj.db` (by SHA-256 over SSH), copies every work with a config in `scripts/lyceum-imports/` into
`conllu/lyceum/<work>-<model>/` (`output.conllu`, `units.jsonl`, `config.json`), and commits and tags `vYYYY.MM.DD`
with a manifest in `releases/`. A partly imported work is cut to the passages the served `editions.db` holds; a work
whose imported passages are not a prefix of its `units.jsonl` stops the release until it is re-imported. The
zstd-compressed databases, `SHA256SUMS.txt`, `manifest.json`, `NOTES.md`, and the website's `DATA_PROVENANCE.md` are
staged in `ARCHEION_RELEASE_DIR/<version>/` (default `/var/tmp/archeion-releases`). `users.db` is never read.

```sh
kai run publish-archeion                 # production; nothing leaves this machine
ARCHEION_PUSH=1 kai run push-archeion    # master + tag to ARCHEION_REMOTES (default origin)
ARCHEION_GITHUB_RELEASE=1 kai run release-archeion-github   # needs the tag on GitHub

# All of it, after deploying the data to production:
LYCEUM_DEPLOY_PRODUCTION=1 ARCHEION_PUSH=1 ARCHEION_GITHUB_RELEASE=1 kai workflow release-lyceum
```

`publish-archeion-staging` rehearses against staging and tags `vYYYY.MM.DD-staging`; `release-archeion-github`
refuses anything not verified against production. Set `ARCHEION_VERSION=vYYYY.MM.DD.2` for a second release on the
same day.
