app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# Puts Archeion's data into Lyceum Study (the study app at study.lyceum.quest; its repository is LYCEUM_STUDY_DIR).
#   stage:   packs conllu/generated/ as a preload release on this machine (release-preload.roc build aristos, which
#            tags HEAD preload-<version>; the version is today's vYYYY.MM.DD, or .2, .3, ... if that tag exists),
#            pins it in Lyceum Study's preload.lock.json (committed there), builds Lyceum Study's staging release from
#            the local archive (ARISTOS_PRELOAD_ARCHIVE, checked against the pin) and deploys it to the staging host.
#            Nothing is published.
#   promote: publishes the release Lyceum Study pins: pushes its tag, creates the GitHub release
#            (release-preload.roc github aristos; needs ARCHEION_GITHUB_RELEASE=1), pushes Lyceum Study, then builds
#            its production release, which downloads the published archive and checks it against the same pin, and
#            deploys it (needs ARISTOS_DEPLOY_PRODUCTION=1).
# The deploy hosts are LYCEUM_STAGING_HOST and LYCEUM_PROD_HOST, the same hosts as the Lyceum website's data.
# KAI names the kai program (default `kai`).
# Usage: roc scripts/study.roc stage|promote

main! = |args| {
	study = study_dir!({})?
	kai = if setting!("KAI") == "" "kai" else setting!("KAI")
	releases = if setting!("ARCHEION_RELEASE_DIR") == "" "/var/tmp/archeion-releases" else setting!("ARCHEION_RELEASE_DIR")
	match args.map(OsStr.display) {
		[_, "stage"] => {
			version = free_version!(run!("date", ["-u", "+v%Y.%m.%d"])?, 1)?
			tag = "preload-${version}"
			_ = Stdout.line!("Packing ${tag}")?
			_ = Cmd.new_str("roc").args_str(["scripts/release-preload.roc", "build", "aristos"]).env_str("ARCHEION_VERSION", version).exec_cmd!()?
			archive = "${releases}/${tag}/aristos-preload.tar.zst"
			sum = List.first(Str.split_on(run!("sha256sum", ["--", archive])?, " ")) ?? ""
			github = if setting!("ARCHEION_GITHUB_REPO") == "" "lyceum-quest/archeion" else setting!("ARCHEION_GITHUB_REPO")
			lock = "{\n  \"release\": \"${tag}\",\n  \"url\": \"https://github.com/${github}/releases/download/${tag}/aristos-preload.tar.zst\",\n  \"sha256\": \"${sum}\"\n}\n"
			_ = Path.write_utf8!(Path.utf8("${study}/preload.lock.json"), lock)?
			changed = run!("git", ["-C", study, "status", "--porcelain", "--", "preload.lock.json"])? != ""
			_ = run!("git", ["-C", study, "add", "preload.lock.json"])?
			_ = (if !changed Ok("") else run!("git", ["-C", study, "commit", "--quiet", "--message", "data: pin Archeion ${tag}\n\nStaged by Archeion's release-staging; the archive is published when it is promoted\n(release-production), before this build reaches production."]))?
			host = if setting!(LyceumWebsite.staging_host) == "" "lyceum-staging" else setting!(LyceumWebsite.staging_host)
			_ = in_study!(study, kai, ["workflow", "release-staging"], [("ARISTOS_PRELOAD_ARCHIVE", archive)])?
			_ = in_study!(study, kai, ["run", "deploy-site", "--", "staging"], [("ARISTOS_DEPLOY_HOST", host)])?
			Stdout.line!("Lyceum Study staging now serves ${tag} (${sum}). Promote with release-production.")
		}
		[_, "promote"] => {
			pinned : { release : Str, url : Str, sha256 : Str }
			pinned = Json.parse(Path.read_utf8!(Path.utf8("${study}/preload.lock.json"))?)?
			version = Str.drop_prefix(pinned.release, "preload-")
			_ = run!("git", ["push", "origin", "refs/tags/${pinned.release}"])?
			_ = Cmd.new_str("roc").args_str(["scripts/release-preload.roc", "github", "aristos"]).env_str("ARCHEION_VERSION", version).exec_cmd!()?
			_ = run!("git", ["-C", study, "push", "origin", "HEAD"])?
			host = if setting!(LyceumWebsite.production_host) == "" "lyceum-prod" else setting!(LyceumWebsite.production_host)
			_ = in_study!(study, kai, ["workflow", "release"], [])?
			_ = in_study!(study, kai, ["run", "deploy-site", "--", "production"], [("ARISTOS_DEPLOY_HOST", host)])?
			Stdout.line!("Published ${pinned.release} and deployed Lyceum Study to production.")
		}
		_ => Err(Usage("roc scripts/study.roc stage|promote"))
	}
}

# vYYYY.MM.DD, or the first of .2 to .9 whose preload tag is free.
free_version! = |base, n| {
	version = if n == 1 base else "${base}.${U64.to_str(n)}"
	match run!("git", ["rev-parse", "--verify", "--quiet", "refs/tags/preload-${version}"]) {
		Ok(_) => if n >= 9 Err(Study("preload tags ${base} to ${base}.9 all exist; set a new date")) else free_version!(base, n + 1)
		Err(_) => Ok(version)
	}
}

# Runs kai in Lyceum Study's checkout with extra environment variables (the per-run switches it needs are passed
# through from this environment).
in_study! = |study, kai, args, envs| {
	quoted = Str.join_with(List.map(List.concat([kai], args), quote), " ")
	exports = Str.join_with(List.map(envs, |(k, v)| "${k}=${quote(v)}"), " ")
	Cmd.new_str("sh").args_str(["-c", "cd ${quote(study)} && ${exports} ${quoted}"]).exec_cmd!()
}

quote = |s| "'${Str.replace_each(s, "'", "'\\''")}'"

study_dir! = |{}| {
	dir = setting!("LYCEUM_STUDY_DIR")
	if dir == "" {
		Err(MissingStudyDir("set LYCEUM_STUDY_DIR to the Lyceum Study checkout, in the environment or in .env (see .env.example)"))
	} else if Path.is_dir!(Path.utf8(dir)) ?? Bool.False {
		Ok(dir)
	} else {
		Err(MissingStudyDir("LYCEUM_STUDY_DIR=${dir} is not a directory"))
	}
}

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Study("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")
