app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# The changelogs of Archeion, the Lyceum website (LYCEUM_WEBSITE_DIR) and Lyceum Study (LYCEUM_STUDY_DIR): each
# repository's CHANGELOG.md follows Keep a Changelog, with an "## [Unreleased]" section on top; its last release is
# its newest release-YYYY.MM.DD tag. The sites show these files without Internal sections or HTML comments.
#   draft:   under each Unreleased heading, (re)writes an HTML comment listing what changed since the last release:
#            the commits, and (website and Lyceum Study) the Lyceum Editions added or extended, from the website's
#            data/lyceum-editions.json. Describe them in reader language in the entries below it, then delete it. Committed, not
#            pushed. release-staging runs this last.
#   release: dates each Unreleased section that has entries (## [YYYY-MM-DD], a fresh Unreleased above it), drops
#            the drafts, commits, and tags release-YYYY.MM.DD (.2, .3, ... if taken), then pushes each repository and
#            its tag (needs ARCHEION_PUSH=1). release-production runs this first, so production builds include it.
# Usage: roc scripts/changelog.roc draft|release

draft_start = "<!-- release draft"

main! = |args| {
	website = required_dir!("LYCEUM_WEBSITE_DIR")?
	study = required_dir!("LYCEUM_STUDY_DIR")?
	repos = [("Archeion", ".", Bool.False), ("Lyceum", website, Bool.True), ("Lyceum Study", study, Bool.True)]
	match args.map(OsStr.display) {
		[_, "draft"] => draft_all!(repos, website)
		[_, "release"] => {
			_ = if switch!("ARCHEION_PUSH") Ok({}) else Err(Changelog("release pushes each repository: set ARCHEION_PUSH=1"))?
			date = run!("date", ["-u", "+%Y-%m-%d"])?
			release_all!(repos, date)
		}
		_ => Err(Usage("roc scripts/changelog.roc draft|release"))
	}
}

draft_all! = |repos, website|
	match repos {
		[] => Ok({})
		[(name, dir, with_data), .. as rest] => {
			base = last_release!(dir)
			range = match base {
				Ok(tag) => "${tag}..HEAD"
				Err(_) => "HEAD"
			}
			commits = run!("git", ["-C", dir, "log", "--no-merges", "--format=- %h %s", range])?
			data = if with_data data_changes!(website, base) else Ok("")
			since = match base {
				Ok(tag) => tag
				Err(_) => "the beginning"
			}
			comment = "${draft_start} (Archeion's changelog.roc): what changed since ${since}. Describe it in the entries below, in reader language (Internal for the rest), then delete this comment.\n${data?}Commits:\n${if commits == "" "- none" else commits}\n-->"
			path = "${dir}/CHANGELOG.md"
			text = Path.read_utf8!(Path.utf8(path))?
			updated = with_draft(text, comment)?
			_ = (
				if updated == text {
					Stdout.line!("${name}: draft unchanged")
				} else {
					_ = Path.write_utf8!(Path.utf8(path), updated)?
					_ = run!("git", ["-C", dir, "add", "CHANGELOG.md"])?
					_ = run!("git", ["-C", dir, "commit", "--quiet", "--message", "changelog: refresh the release draft"])?
					Stdout.line!("${name}: release draft written in ${path}")
				}
			)?
			draft_all!(rest, website)
		}
	}

# Replaces the draft comment under "## [Unreleased]" (or adds one there).
with_draft = |text, comment| {
	heading = "## [Unreleased]"
	match Str.split_first(text, heading) {
		Ok({ before, after }) => {
			rest = drop_draft(after)
			Ok("${before}${heading}\n\n${comment}\n${rest}")
		}
		Err(_) => Err(Changelog("CHANGELOG.md has no ## [Unreleased] heading"))
	}
}

# The text after the Unreleased heading, without a leading draft comment and the blank lines around it.
drop_draft = |after| {
	trimmed = Str.trim_start(after)
	if Str.starts_with(trimmed, draft_start) {
		match Str.split_first(trimmed, "-->") {
			Ok({ before: _, after: rest }) => "\n${Str.trim_start(rest)}"
			Err(_) => after
		}
	} else {
		"\n${trimmed}"
	}
}

# Lyceum Editions added or extended since a release, from the website's data/lyceum-editions.json.
data_changes! = |website, base| {
	now = editions!(run!("git", ["-C", website, "show", "HEAD:data/lyceum-editions.json"]) ?? "")
	before = match base {
		Ok(tag) => editions!(run!("git", ["-C", website, "show", "${tag}:data/lyceum-editions.json"]) ?? "")
		Err(_) => []
	}
	lines = List.keep_oks(
		now,
		|e| {
			old = List.first(List.keep_if(before, |b| b.folder == e.folder))
			match old {
				Ok(o) if o.passages == e.passages and o.source == e.source => Err(Same)
				Ok(o) if o.passages != e.passages => Ok("- ${e.title}: ${U64.to_str(o.passages)} -> ${U64.to_str(e.passages)} passages")
				Ok(_) => Ok("- ${e.title}: revised (${U64.to_str(e.passages)} passages)")
				Err(_) => Ok("- ${e.title}: ${U64.to_str(e.passages)} passages${if List.is_empty(before) "" else " (new)"}")
			}
		},
	)
	Ok(if List.is_empty(lines) "" else "Lyceum Editions:\n${Str.join_with(lines, "\n")}\n")
}

editions! = |text| {
	parsed : { editions : List({ folder : Str, title : Str, passages : U64, source : Str }) }
	parsed = Json.parse(text) ?? { editions: [] }
	parsed.editions
}

release_all! = |repos, date|
	match repos {
		[] => Ok({})
		[(name, dir, _), .. as rest] => {
			path = "${dir}/CHANGELOG.md"
			text = Path.read_utf8!(Path.utf8(path))?
			heading = "## [Unreleased]"
			_ = match Str.split_first(text, heading) {
				Ok({ before, after }) => {
					body = drop_draft(after)
					next = match Str.split_first(body, "\n## ") {
						Ok({ before: entries, after: _ }) => entries
						Err(_) => body
					}
					if !Str.contains(next, "\n- ") {
						Stdout.line!("${name}: nothing unreleased")
					} else {
						tag = free_tag!(dir, "release-${Str.replace_each(date, "-", ".")}", 1)?
						_ = Path.write_utf8!(Path.utf8(path), "${before}${heading}\n\n## [${date}]\n${body}")?
						_ = run!("git", ["-C", dir, "add", "CHANGELOG.md"])?
						_ = run!("git", ["-C", dir, "commit", "--quiet", "--message", "Release ${date}"])?
						_ = run!("git", ["-C", dir, "tag", "--annotate", tag, "--message", "Release ${date}"])?
						_ = run!("git", ["-C", dir, "push", "origin", "HEAD", "refs/tags/${tag}"])?
						Stdout.line!("${name}: released ${date} (${tag}), pushed")
					}
				}
				Err(_) => Err(Changelog("${path} has no ## [Unreleased] heading"))
			}?
			release_all!(rest, date)
		}
	}

free_tag! = |dir, base, n| {
	tag = if n == 1 base else "${base}.${U64.to_str(n)}"
	match run!("git", ["-C", dir, "rev-parse", "--verify", "--quiet", "refs/tags/${tag}"]) {
		Ok(_) => if n >= 9 Err(Changelog("${base} to ${base}.9 are all taken")) else free_tag!(dir, base, n + 1)
		Err(_) => Ok(tag)
	}
}

last_release! = |dir| {
	tag = run!("git", ["-C", dir, "describe", "--tags", "--abbrev=0", "--match", "release-*", "HEAD"])?
	if tag == "" Err(NoRelease) else Ok(tag)
}

required_dir! = |key| {
	dir = setting!(key)
	if dir == "" {
		Err(Changelog("set ${key} in the environment or in .env (see .env.example)"))
	} else if Path.is_dir!(Path.utf8(dir)) ?? Bool.False {
		Ok(dir)
	} else {
		Err(Changelog("${key}=${dir} is not a directory"))
	}
}

switch! = |name| (Env.var_str!(OsStr.from_str(name)) ?? "") == "1"

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Changelog("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")
