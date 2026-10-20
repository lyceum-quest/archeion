app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumImportSql
import LyceumWebsite

# Brings the Lyceum website's reader databases (LYCEUM_WEBSITE_DIR/data/texts.db and editions.db) up to date with
# Archeion. The works on the site are the ones with a config in scripts/lyceum-imports/ (as publish-archeion counts
# them). The website records what it holds in data/lyceum-editions.json: each work's passages and a fingerprint of
# the Archeion files it was imported from. A work is imported when its fingerprint or passage count differs; one
# that matches is left alone, so a sync with nothing new writes nothing (a re-import would renumber the database's
# rows even for identical texts).
# Without --apply nothing is written: it lists each work's passages in Archeion and in Lyceum, and what would be
# imported. With --apply it backs up both databases once (texts.db is large: a backup per work would fill the disk;
# the previous sync's backups are removed first), prepares and imports each work that needs it
# (lyceum-import-config.roc, keeping a work's --replace editions, as for Meditations; then import-lyceum.roc),
# checks every count matches, and commits data/editions.db and data/lyceum-editions.json in the website checkout
# (texts.db is not in git). `push` pushes that checkout's branch to its origin. Deploy with deploy-lyceum-data.
# Usage: roc scripts/sync-lyceum.roc [--apply | push]

imports_dir = "scripts/lyceum-imports"

record_path = "data/lyceum-editions.json"

Work : { folder : Str, config_path : Str, greek_urn : Str, replace_args : List(Str), title : Str, source : Str, passages : U64 }

Recorded : { folder : Str, title : Str, passages : U64, source : Str }

main! = |args| {
	website = website_dir!({})?
	match args.map(OsStr.display) {
		[_] => sync!(website, Bool.False)
		[_, "--apply"] => sync!(website, Bool.True)
		[_, "push"] => {
			_ = run!("git", ["-C", website, "push", "origin", "HEAD"])?
			Stdout.line!("pushed ${website} to origin")
		}
		_ => Err(Usage("roc scripts/sync-lyceum.roc [--apply | push]"))
	}
}

sync! = |website, apply| {
	texts_db = "${website}/data/texts.db"
	editions_db = "${website}/data/editions.db"
	recorded = read_record!(website)
	works = List.sort_with(collect_works!(Path.list!(Path.utf8(imports_dir))?, [])?, |a, b| compare_str(a.folder, b.folder))
	_ = Stdout.line!("Lyceum Editions (passages in Archeion / in Lyceum):")?
	todo = plan!(works, recorded, editions_db, [])?
	if List.is_empty(todo) {
		Stdout.line!("Lyceum matches Archeion; nothing to import.")
	} else if !apply {
		Stdout.line!("${U64.to_str(List.len(todo))} work(s) to import. Nothing written (dry run); --apply imports them after one backup of both databases.")
	} else {
		_ = remove_old_backups!(Path.list!(Path.utf8("${website}/data"))?)?
		_ = backup!(texts_db)?
		_ = backup!(editions_db)?
		_ = import_all!(todo)?
		_ = Stdout.line!("After the sync:")?
		left = plan!(works, List.map(works, |w| { folder: w.folder, title: w.title, passages: w.passages, source: w.source }), editions_db, [])?
		if List.is_empty(left) {
			_ = Path.write_utf8!(Path.utf8("${website}/${record_path}"), record_json(works))?
			_ = commit_data!(website, todo)?
			Stdout.line!("Lyceum matches Archeion. Deploy with: kai run deploy-lyceum-data")
		} else {
			Err(Sync("${U64.to_str(List.len(left))} work(s) still differ after importing"))
		}
	}
}

# Prints each work and returns the ones to import: a new fingerprint, or Lyceum's count differing from Archeion's.
plan! = |works, recorded, editions_db, todo|
	match works {
		[] => Ok(todo)
		[work, .. as rest] => {
			lyceum = lyceum_passages!(editions_db, work.greek_urn)?
			known = List.keep_if(recorded, |r| r.folder == work.folder)
			same_source = List.any(known, |r| r.source == work.source)
			needed = !same_source or lyceum != work.passages
			reason = if lyceum != work.passages "  <- import (counts differ)" else if !same_source "  <- import (Archeion changed)" else ""
			_ = Stdout.line!("  ${work.folder}: ${U64.to_str(work.passages)} / ${U64.to_str(lyceum)}${reason}")?
			plan!(rest, recorded, editions_db, if needed List.append(todo, work) else todo)
		}
	}

read_record! = |website| {
	text = Path.read_utf8!(Path.utf8("${website}/${record_path}")) ?? "{ \"editions\": [] }"
	parsed : { editions : List(Recorded) }
	parsed = Json.parse(text) ?? { editions: [] }
	parsed.editions
}

record_json = |works| {
	entry = |w| "    { \"folder\": ${json_str(w.folder)}, \"title\": ${json_str(w.title)}, \"passages\": ${U64.to_str(w.passages)}, \"source\": ${json_str(w.source)} }"
	"{\n  \"note\": \"Lyceum Editions this website holds, written by Archeion's sync-lyceum. source: SHA-256 of the work's Archeion files.\",\n  \"editions\": [\n${Str.join_with(List.map(works, entry), ",\n")}\n  ]\n}\n"
}

json_str = |s| "\"${Str.replace_each(Str.replace_each(s, "\\", "\\\\"), "\"", "\\\"")}\""

# Commits data/editions.db and the record in the website checkout, naming the imported works and this Archeion commit.
commit_data! = |website, imported| {
	changed = run!("git", ["-C", website, "status", "--porcelain", "--", "data/editions.db", record_path])? != ""
	if changed {
		archeion = run!("git", ["rev-parse", "--short", "HEAD"])?
		lines = Str.join_with(List.map(imported, |w| "- ${w.title}: ${U64.to_str(w.passages)} passages"), "\n")
		_ = run!("git", ["-C", website, "add", "--", "data/editions.db", record_path])?
		_ = run!("git", ["-C", website, "commit", "--quiet", "--message", "data: sync Lyceum Editions from Archeion ${archeion}\n\n${lines}\n\nWritten by Archeion's sync-lyceum."])?
		Stdout.line!("committed data/editions.db and ${record_path} in ${website}")
	} else {
		Stdout.line!("nothing to commit")
	}
}

# One Work per scripts/lyceum-imports/<folder>.json, with its Archeion passages, title, and source fingerprint.
collect_works! = |entries, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			name = List.last(Str.split_on(path, "/")) ?? path
			if Str.ends_with(name, ".json") {
				folder = Str.drop_suffix(name, ".json")
				config : LyceumImportSql.Config
				config = Json.parse(Path.read_utf8!(entry)?)?
				dir = "conllu/generated/${folder}"
				units = Path.read_utf8!(Path.utf8("${dir}/units.jsonl"))?
				passages = List.len(List.keep_if(Str.split_on(units, "\n"), |line| Str.trim(line) != ""))
				settings : { title : Str }
				settings = Json.parse(Path.read_utf8!(Path.utf8("${dir}/config.json"))?) ?? { title: folder }
				sums = run!("sha256sum", ["--", "${dir}/output.conllu", "${dir}/units.jsonl", "${dir}/config.json", path])?
				source = List.first(Str.split_on(run!("sh", ["-c", "printf %s \"$1\" | sha256sum", "sh", sums])?, " ")) ?? ""
				(greek_urn, replace_args) = match (config.edition_slug, config.replace_editions) {
					(Ok(slug), Err(Missing)) => Ok(("${config.work_urn}.${slug}-grc1", []))
					(Err(Missing), Ok(editions)) => Ok((editions.greek_urn, ["--replace", editions.greek_urn, editions.english_urn]))
					_ => Err(Sync("${path}: specify exactly one of edition_slug or replace_editions"))
				}?
				work = { folder, config_path: path, title: settings.title, source, passages, greek_urn, replace_args }
				collect_works!(rest, List.append(found, work))
			} else {
				collect_works!(rest, found)
			}
		}
	}

lyceum_passages! = |editions_db, urn| {
	quoted = Str.replace_each(urn, "'", "''")
	count = run!("sqlite3", ["-readonly", editions_db, "SELECT count(*) FROM segments s JOIN editions e ON e.id = s.edition_id WHERE e.urn = '${quoted}';"])?
	Ok(U64.from_str(count) ? |_| Sync("unexpected count for ${urn}: ${count}"))
}

import_all! = |works|
	match works {
		[] => Ok({})
		[work, .. as rest] => {
			_ = Stdout.line!("== ${work.folder}")?
			_ = Cmd.new_str("roc").args_str(List.concat(["scripts/lyceum-import-config.roc", "conllu/generated/${work.folder}"], work.replace_args)).exec_cmd!()?
			_ = Cmd.new_str("roc")
				.args_str(["scripts/import-lyceum.roc"])
				.env_str("LYCEUM_IMPORT_CONFIG", work.config_path)
				.env_str("LYCEUM_IMPORT_APPLY", "1")
				.env_str("LYCEUM_IMPORT_BACKUP", "0")
				.exec_cmd!()?
			import_all!(rest)
		}
	}

# The previous sync's backups (<db>.before-sync-*), so backups don't pile up.
remove_old_backups! = |entries|
	match entries {
		[] => Ok({})
		[entry, .. as rest] => {
			path = Path.display(entry)
			_ = if Str.contains(path, ".before-sync-") run!("rm", ["-f", "--", path]) else Ok("")
			remove_old_backups!(rest)
		}
	}

backup! = |path| {
	stamp = run!("date", ["+%Y%m%d-%H%M%S"])?
	backup = "${path}.before-sync-${stamp}"
	_ = run!("sqlite3", ["-readonly", path, ".backup \"${backup}\""])?
	Stdout.line!("backup: ${backup}")
}

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = |x, y|
	match (x, y) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([a, .. as xs], [b, .. as ys]) => if a < b Before else if a > b After else compare_bytes(xs, ys)
	}

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Sync("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")

website_dir! = |{}| {
	dir = LyceumWebsite.dir(setting!(LyceumWebsite.name))?
	if Path.is_dir!(Path.utf8(dir)) ?? Bool.False Ok(dir) else Err(MissingWebsiteDir("${LyceumWebsite.name}=${dir} is not a directory"))
}
