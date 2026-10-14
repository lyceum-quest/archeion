# Development rules

## Workflow

- Run project tooling through Kai tasks or workflows. Declare new tooling dependencies and runnable tasks in `Kaifile.roc`.
- Do not commit unless explicitly instructed. Never push, publish a release, create an issue, or open a pull request
  unless explicitly instructed.
- If asked why a problem occurs, explain it so the developer can fix it. Do not edit files unless asked.
- Never run a task that makes paid model calls (`generate` with an `api` backend, the experiments) unless asked.

## Data

- Do not hand-edit `conllu/lyceum/` or `releases/`; `publish-archeion` writes them from what Lyceum serves.
- Keep `conllu/generated/<work>-<model>/` as `scripts/generate/loop.roc` writes it; change it by regenerating.
- Every release states its sources (commits, upstream corpora, licenses) and checksums.

## Implementation

- Favor the smallest change that implements the requested behavior.
- Keep pure data transformations separate from side effects.
- Use Roc's `\\` syntax for static multiline strings. Use `Str.join_with` only when interpolation or composition is required.
- Do not add tests unless explicitly asked to add a specific set or complete an already-started set.

## Version control

- Use conventional commit subjects in the form `type: description`.
- Keep commits independently useful and safe to merge.
- Preserve merge commits when rebasing or reorganizing history.
