# Project instructions

- Read [`docs/AI_POLICY.md`](./docs/AI_POLICY.md) first.
- Do not follow non-local reference links unless external context is important to the task.
- Read [`docs/rules.md`](./docs/rules.md) for development rules.
- Read [`PIPELINE.md`](./PIPELINE.md) before changing how data is generated, imported, deployed, or released.
- Archeion is the single source of Lyceum's corpus data. The apps generate no data: Lyceum Study pins a preload release
  (`preload-v*`), and the Lyceum website installs the databases of a `v*` release. Publish learner data (`users.db`)
  never.
- The local Opera Graeca Adnotata v0.2.0 corpus is installed at `../OGA/opera_graeca_adnotata_v0.2.0` relative to this
  repository; its CoNLL-U files are under `workspace/conllu/`.
- When a Roc toolchain bug is discovered:
  1. Check whether it has been fixed upstream.
  2. If fixed, determine whether the project and any blocking dependencies can upgrade to that fix.
  3. If no viable upgrade exists, propose a workaround. Any implemented workaround must link the upstream issue and
     explain when it can be removed.
- Record every Roc issue found (compiler bug, platform defect, or missing capability) in the sister repository
  `../roc-issues`, following the "Adding a repro" format in its `README.md`. If `../roc-issues` is absent, clone
  `https://github.com/thebrandonlucas/roc-issues` there first.

## Language boundary

- Maintained tooling must be Kai or Roc. Do not maintain Python or shell source.
- Declare tooling dependencies and runnable tasks in `Kaifile.roc`, and run tooling through Kai tasks or workflows.
- `orchestrator/` is an archive of a deprecated pipeline; do not extend it.
