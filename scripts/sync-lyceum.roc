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
# them); each is prepared afresh from its conllu/generated/ folder (lyceum-import-config.roc, keeping a work's
# --replace editions, as for Meditations) and imported (import-lyceum.roc). An import replaces the work's passages,
# so an unchanged work comes out the same and an extended one gains its new passages.
# Without --apply nothing is written: it lists each work's passages in Archeion and in the website's editions.db.
# With --apply it backs up both databases once (texts.db is large: a backup per work would fill the disk; the
# previous sync's backups are removed first), imports every work, and lists the counts again. Deploy the result
# with deploy-lyceum-data. A changed data/editions.db is committed in the website checkout (texts.db is not in git);
# `push` pushes that checkout's branch to its origin.
# Usage: roc scripts/sync-lyceum.roc [--apply | push]

imports_dir = "scripts/lyceum-imports"

Work : { folder : Str, config_path : Str, greek_urn : Str, replace_args : List(Str) }

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
	works = List.sort_with(collect_works!(Path.list!(Path.utf8(imports_dir))?, [])?, |a, b| compare_str(a.folder, b.folder))
	_ = Stdout.line!("Lyceum Editions (passages in Archeion / in ${editions_db}):")?
	changes = report!(works, editions_db, 0)?
	if !apply {
		Stdout.line!(
			if changes == 0 {
				"Lyceum matches Archeion. Nothing written (dry run)."
			} else {
				"${U64.to_str(changes)} work(s) differ. Nothing written (dry run); --apply imports every work after one backup of both databases."
			},
		)
	} else {
		_ = remove_old_backups!(Path.list!(Path.utf8("${website}/data"))?)?
		_ = backup!(texts_db)?
		_ = backup!(editions_db)?
		_ = import_all!(works)?
		_ = Stdout.line!("After the sync:")?
		left = report!(works, editions_db, 0)?
		if left == 0 {
			_ = commit_data!(website)?
			Stdout.line!("Lyceum matches Archeion. Deploy with: kai run deploy-lyceum-data")
		} else {
			Err(Sync("${U64.to_str(left)} work(s) still differ after importing"))
		}
	}
}

# Commits the website's data/editions.db if the sync changed it, naming this Archeion commit.
commit_data! = |website| {
	changed = run!("git", ["-C", website, "status", "--porcelain", "--", "data/editions.db"])? != ""
	if changed {
		archeion = run!("git", ["rev-parse", "--short", "HEAD"])?
		_ = run!("git", ["-C", website, "add", "--", "data/editions.db"])?
		_ = run!("git", ["-C", website, "commit", "--quiet", "--message", "data: sync Lyceum Editions from Archeion ${archeion}\n\nWritten by Archeion's sync-lyceum: every work in its scripts/lyceum-imports/."])?
		Stdout.line!("committed data/editions.db in ${website}")
	} else {
		Stdout.line!("data/editions.db unchanged; nothing to commit")
	}
}

# One Work per scripts/lyceum-imports/<folder>.json.
collect_works! = |entries, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			name = List.last(Str.split_on(path, "/")) ?? path
			if Str.ends_with(name, ".json") {
				config : LyceumImportSql.Config
				config = Json.parse(Path.read_utf8!(entry)?)?
				work = match (config.edition_slug, config.replace_editions) {
					(Ok(slug), Err(Missing)) => Ok({ folder: Str.drop_suffix(name, ".json"), config_path: path, greek_urn: "${config.work_urn}.${slug}-grc1", replace_args: [] })
					(Err(Missing), Ok(editions)) => Ok({ folder: Str.drop_suffix(name, ".json"), config_path: path, greek_urn: editions.greek_urn, replace_args: ["--replace", editions.greek_urn, editions.english_urn] })
					_ => Err(Sync("${path}: specify exactly one of edition_slug or replace_editions"))
				}?
				collect_works!(rest, List.append(found, work))
			} else {
				collect_works!(rest, found)
			}
		}
	}

# Prints each work's counts and returns how many differ.
report! = |works, editions_db, differing|
	match works {
		[] => Ok(differing)
		[work, .. as rest] => {
			archeion = archeion_passages!(work)?
			lyceum = lyceum_passages!(editions_db, work.greek_urn)?
			same = archeion == lyceum
			_ = Stdout.line!("  ${work.folder}: ${U64.to_str(archeion)} / ${U64.to_str(lyceum)}${if same "" else "  <- differs"}")?
			report!(rest, editions_db, if same differing else differing + 1)
		}
	}

# One passage per line of units.jsonl (lyceum-import-config makes one Lyceum passage of each).
archeion_passages! = |work| {
	units = Path.read_utf8!(Path.utf8("conllu/generated/${work.folder}/units.jsonl"))?
	Ok(List.len(List.keep_if(Str.split_on(units, "\n"), |line| Str.trim(line) != "")))
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

compare_str = |a, b| {
	x = Str.to_utf8(a)
	y = Str.to_utf8(b)
	compare_bytes(x, y)
}

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
