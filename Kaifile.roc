app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.8/9b3Nr3mzNr1rEm3xPgFaaAFaizQS1SfcvHUsSDnEcy2S.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.8/std-96MVndfriX4HRuFzHn5735BuvzH1mYdhkm5JeuoTDg96.tar.zst",
}

import std.Std

kaifile = Std.kaifile([
	Name("archeion"),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Environment(
		"dev",
		[
			Tools([
				"bashInteractive",
				"coreutils",
				"curl",
				"gh",
				"git",
				"gnugrep",
				"gnutar",
				"openssh",
				"rocpkgs.nightly-2026-09-19-d025939",
				"rsync",
				"sqlite",
				"unzip",
				"zstd",
			]),
			Overlays(["roc"]),
		],
	),
	Shell("default", [Use("dev")]),

	# kai run generate -- <work> <config.json> <passage-count|all>
	# e.g. kai run generate -- 1peter scripts/generate/works/1peter.json 25
	# Glosses sentences and translates canonical passages (verses, sections; see
	# scripts/Passages.roc) into conllu/generated/<work>-<model>/, resuming its
	# checkpoints; missing work makes model calls. Meditations Book 1 is 42.
	# A work config's optional "backend" picks how calls are made: "api" (the
	# default; paid per call through base_url) or "subscription" (`claude -p` on
	# this machine's Claude Code login; see scripts/generate/Backend.roc). Works
	# can switch between runs; costs.tsv records each call's backend.
	# SIGINT is ignored so Ctrl-C stops the current stage and the loop reports;
	# see ../roc-issues/improvements/IMPROVEMENT-002-basic-cli-sigint-handling.
	Task("generate", [Use("dev"), Run(["env", "--ignore-signal=INT", "roc", "scripts/generate/loop.roc"])]),

	Task("check-loop", [Use("dev"), Run(["roc", "check", "scripts/generate/loop.roc"])]),

	Task("check-translate", [Use("dev"), Run(["roc", "check", "scripts/generate/translate.roc"])]),

	Task("check-gloss", [Use("dev"), Run(["roc", "check", "scripts/generate/gloss.roc"])]),

	# kai run lint -- <dir>: checks the .conllu files under <dir>. Nothing passes yet: it predates the generated
	# works and expects a `# global.columns` header they lack.
	Task("lint", [Use("dev"), Run(["roc", "scripts/lint.roc"])]),

	Task("check-lint-tool", [Use("dev"), Run(["roc", "check", "scripts/lint.roc"])]),

	# kai run vendor-oga-refs -- <opera_graeca_adnotata_v0.2.0.zip> <cts-id>...
	# Vendors OGA's canonical citation layer into data/oga/refs/<cts-id>.tsv, which
	# scripts/Passages.roc uses to group each work into verses or sections.
	Task("vendor-oga-refs", [Use("dev"), Run(["roc", "devtools/vendor-oga-refs.roc"])]),

	Task("check-passages-tool", [Use("dev"), Run(["roc", "check", "scripts/passages.roc"])]),

	# kai run cite -- <oga-input.conllu> <model>
	# Prints the citation preload derives from data/oga/urn_cts.xml; fails if it would be incomplete.
	Task("cite", [Use("dev"), Run(["roc", "scripts/cite.roc"])]),

	Task("check-cite-tool", [Use("dev"), Run(["roc", "check", "scripts/cite.roc"])]),

	# Bundles every conllu/generated/<work>-<model>/ folder with output.conllu and config.json as corpus <work>,
	# including partially generated works, into preload/ (git-ignored) for inspection; releases build their own.
	Task("preload", [Use("dev"), Run(["roc", "scripts/build-corpus-preload.roc", "preload", "conllu/generated"])]),

	Task("check-preload-tool", [Use("dev"), Run(["roc", "check", "scripts/build-corpus-preload.roc"])]),

	# Builds the committed works' preload into ARCHEION_RELEASE_DIR/preload-<version>/ and tags preload-<version>.
	Task("release-preload", [Use("dev"), Run(["roc", "scripts/release-preload.roc", "build", "aristos"])]),

	# Requires ARCHEION_GITHUB_RELEASE=1 and the preload tag on GitHub.
	Task("release-preload-github", [Use("dev"), Run(["roc", "scripts/release-preload.roc", "github", "aristos"])]),

	# The CoNLL-U visualizer's treebanks (conllu/conllu-viz.json lists them), as conllu-viz-<version>; conllu-viz pins
	# it in its data.lock.json.
	Task("release-conllu-viz", [Use("dev"), Run(["roc", "scripts/release-preload.roc", "build", "conllu-viz"])]),

	Task("release-conllu-viz-github", [Use("dev"), Run(["roc", "scripts/release-preload.roc", "github", "conllu-viz"])]),

	Task("check-release-preload-tool", [Use("dev"), Run(["roc", "check", "scripts/release-preload.roc"])]),

	# kai workflow preload-release, then push the tag and run release-preload-github; Lyceum Study pins the release in
	# its preload.lock.json.
	Workflow(
		"preload-release",
		[
			RunTask("check-preload-tool", []),
			RunTask("check-cite-tool", []),
			RunTask("check-release-preload-tool", []),
			RunTask("check-lint-tool", []),
			RunTask("release-preload", []),
		],
	),

	# kai run lyceum-import-config -- <conllu/generated/work-model> [--replace <greek-urn> <english-urn>]
	# Writes the work's passages (one Lyceum passage per units.jsonl passage) to /tmp and
	# scripts/lyceum-imports/<work-model>.json, which imports them.
	Task("lyceum-import-config", [Use("dev"), Run(["roc", "scripts/lyceum-import-config.roc"])]),

	Task("check-lyceum-import-config-tool", [Use("dev"), Run(["roc", "check", "scripts/lyceum-import-config.roc"])]),

	# Export SQL by default. Configs: scripts/lyceum-{import,replace}.example.json. The databases are
	# LYCEUM_WEBSITE_DIR/data/{texts,editions}.db (see .env.example).
	# LYCEUM_IMPORT_CONFIG selects the config; LYCEUM_IMPORT_APPLY=1 writes.
	# Backups default on; LYCEUM_IMPORT_BACKUP=0 explicitly skips them.
	Task("import-lyceum", [Use("dev"), Run(["roc", "scripts/import-lyceum.roc"])]),

	Task("check-lyceum-import", [Use("dev"), Run(["roc", "check", "scripts/import-lyceum.roc"])]),

	Task("format-lyceum-import", [Use("dev"), Run(["roc", "fmt", "scripts/import-lyceum.roc", "scripts/LyceumConllu.roc", "scripts/LyceumImportSql.roc", "scripts/LyceumWebsite.roc", "scripts/lyceum-import-config.roc"])]),

	# Bring Lyceum's databases up to date with every work on the site (scripts/lyceum-imports/): dry run by default,
	# listing each work's passages in Archeion and in Lyceum; `kai run sync-lyceum -- --apply` imports them all after
	# one backup of both databases.
	Task("sync-lyceum", [Use("dev"), Run(["roc", "scripts/sync-lyceum.roc"])]),

	Task("check-sync-lyceum-tool", [Use("dev"), Run(["roc", "check", "scripts/sync-lyceum.roc"])]),

	Task("sync-lyceum-apply", [Use("dev"), Run(["roc", "scripts/sync-lyceum.roc", "--apply"])]),

	Task("push-lyceum-data", [Use("dev"), Run(["roc", "scripts/sync-lyceum.roc", "push"])]),

	# Lyceum Study (LYCEUM_STUDY_DIR): stage packs and pins the preload and deploys the staging site; promote publishes
	# that preload and deploys production (see scripts/study.roc).
	Task("study-stage", [Use("dev"), Run(["roc", "scripts/study.roc", "stage"])]),

	Task("study-promote", [Use("dev"), Run(["roc", "scripts/study.roc", "promote"])]),

	Task("check-study-tool", [Use("dev"), Run(["roc", "check", "scripts/study.roc"])]),

	# The changelogs of Archeion, Lyceum and Lyceum Study (scripts/changelog.roc): draft lists what changed since the
	# last release under each Unreleased heading; release dates them, tags release-YYYY.MM.DD and pushes
	# (ARCHEION_PUSH=1).
	Task("changelog-draft", [Use("dev"), Run(["roc", "scripts/changelog.roc", "draft"])]),

	Task("changelog-release", [Use("dev"), Run(["roc", "scripts/changelog.roc", "release"])]),

	Task("check-changelog-tool", [Use("dev"), Run(["roc", "check", "scripts/changelog.roc"])]),

	# Stage, verify, back up, and replace only the reader's two content databases.
	Task("deploy-lyceum-data", [Use("dev"), Run(["roc", "scripts/deploy-lyceum-data.roc", "staging"])]),

	# Requires LYCEUM_DEPLOY_PRODUCTION=1; never rebuilds the shared host.
	Task("deploy-lyceum-data-prod", [Use("dev"), Run(["roc", "scripts/deploy-lyceum-data.roc", "production"])]),

	Task("check-lyceum-data-deploy", [Use("dev"), Run(["roc", "check", "scripts/deploy-lyceum-data.roc"])]),

	Task("format-lyceum-data-deploy", [Use("dev"), Run(["roc", "fmt", "scripts/deploy-lyceum-data.roc"])]),

	# Snapshot the served databases and imported works into conllu/lyceum/ and releases/ (commit and tag) and
	# ARCHEION_RELEASE_DIR (compressed assets); fails unless the host serves the local databases.
	Task("publish-archeion", [Use("dev"), Run(["roc", "scripts/publish-archeion.roc", "production"])]),

	Task("publish-archeion-staging", [Use("dev"), Run(["roc", "scripts/publish-archeion.roc", "staging"])]),

	# Requires ARCHEION_PUSH=1; pushes master and the release tag to ARCHEION_REMOTES (default origin).
	Task("push-archeion", [Use("dev"), Run(["roc", "scripts/push-archeion.roc", "git"])]),

	# Requires ARCHEION_GITHUB_RELEASE=1, a production snapshot, and its tag on GitHub.
	Task("release-archeion-github", [Use("dev"), Run(["roc", "scripts/push-archeion.roc", "github"])]),

	Task("check-publish-archeion-tool", [Use("dev"), Run(["roc", "check", "scripts/publish-archeion.roc"])]),

	Task("check-push-archeion-tool", [Use("dev"), Run(["roc", "check", "scripts/push-archeion.roc"])]),

	# Deploy the content databases to production, then publish exactly what it serves.
	# Needs LYCEUM_DEPLOY_PRODUCTION=1, ARCHEION_PUSH=1, and ARCHEION_GITHUB_RELEASE=1.
	# A release, staging first: bring Lyceum's data up to date with Archeion (committed and pushed in the website
	# repository), deploy it to Lyceum staging, and stage Lyceum Study with the same data. Nothing is published; look
	# at both staging sites, then promote with release-production.
	Workflow(
		"release-staging",
		[
			RunTask("check-sync-lyceum-tool", []),
			RunTask("check-study-tool", []),
			RunTask("check-changelog-tool", []),
			RunTask("check-lyceum-import", []),
			RunTask("check-lyceum-import-config-tool", []),
			RunTask("check-lyceum-data-deploy", []),
			RunTask("check-release-preload-tool", []),
			RunTask("sync-lyceum-apply", []),
			RunTask("push-lyceum-data", []),
			RunTask("deploy-lyceum-data", []),
			RunTask("study-stage", []),
			RunTask("changelog-draft", []),
		],
	),

	# Promote what staging shows: date the three changelogs (tagged and pushed), Lyceum's data to production and its
	# Archeion release (release-lyceum's steps), then
	# Lyceum Study's pinned preload published and deployed. Needs LYCEUM_DEPLOY_PRODUCTION=1, ARCHEION_PUSH=1,
	# ARCHEION_GITHUB_RELEASE=1, and ARISTOS_DEPLOY_PRODUCTION=1.
	Workflow(
		"release-production",
		[
			RunTask("changelog-release", []),
			RunTask("deploy-lyceum-data-prod", []),
			RunTask("publish-archeion", []),
			RunTask("push-archeion", []),
			RunTask("release-archeion-github", []),
			RunTask("study-promote", []),
		],
	),

	Workflow(
		"release-lyceum",
		[
			RunTask("deploy-lyceum-data-prod", []),
			RunTask("publish-archeion", []),
			RunTask("push-archeion", []),
			RunTask("release-archeion-github", []),
		],
	),
])
