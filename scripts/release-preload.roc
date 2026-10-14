app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# Packs the Aristos preload (corpora.json, corpora/, lemmas.json; see build-corpus-preload.roc) built from the committed
# conllu/generated/ as a release that Aristos pins in its preload.lock.json and fetches.
#   build:  writes ARCHEION_RELEASE_DIR/preload-<version>/aristos-preload.tar.zst (reproducible: sorted, zero mtimes and
#           owners) and SHA256SUMS.txt, and tags HEAD preload-<version>. Nothing leaves this machine.
#   github: creates the GitHub release preload-<version> from those files; needs ARCHEION_GITHUB_RELEASE=1 and the tag
#           on GitHub (push it first).
# The version is ARCHEION_VERSION, or else today's vYYYY.MM.DD when building and the newest preload-v* tag otherwise.
# Usage: roc scripts/release-preload.roc build|github
asset = "aristos-preload.tar.zst"

main! = |args| {
	releases = if setting!("ARCHEION_RELEASE_DIR") == "" "/var/tmp/archeion-releases" else setting!("ARCHEION_RELEASE_DIR")
	match args.map(OsStr.display) {
		[_, "build"] => {
			version = match setting!("ARCHEION_VERSION") {
				"" => run!("date", ["-u", "+v%Y.%m.%d"])?
				value => value
			}
			tag = "preload-${version}"
			release = "${releases}/${tag}"
			_ = require(run!("git", ["status", "--porcelain", "--", "conllu/generated", "data/oga", "scripts"])? == "", "conllu/generated, data/oga, or scripts has uncommitted changes")?
			_ = match run!("git", ["rev-parse", "--verify", "--quiet", "refs/tags/${tag}"]) {
				Ok(_) => Err(Publish("tag ${tag} already exists; set ARCHEION_VERSION"))
				Err(_) => Ok({})
			}?
			_ = require(!(Path.exists!(Path.utf8(release)) ?? Bool.False), "${release} already exists")?
			scratch = run!("mktemp", ["-d", "/tmp/archeion-preload.XXXXXXXXXX"])?
			_ = Cmd.new_str("roc").args_str(["scripts/build-corpus-preload.roc", "${scratch}/preload", "conllu/generated"]).exec_cmd!()?
			_ = run!("mkdir", ["-p", "--", release])?
			_ = run!("tar", ["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "--use-compress-program=zstd -19 -T1", "-C", "${scratch}/preload", "-cf", "${release}/${asset}", "corpora.json", "corpora", "lemmas.json"])?
			_ = run!("rm", ["-rf", "--", scratch])?
			sum = run!("sha256sum", ["--", "${release}/${asset}"])?
			_ = Path.write_utf8!(Path.utf8("${release}/SHA256SUMS.txt"), "${Str.replace_each(sum, "${release}/", "")}\n")?
			_ = run!("git", ["tag", "--annotate", tag, "--message", "Aristos preload ${version}"])?
			Stdout.line!("Tagged ${tag}; ${release}/${asset} is ${List.first(Str.split_on(sum, " ")) ?? ""}. Push the tag, then release with release-preload-github.")
		}
		[_, "github"] => {
			_ = require(switch!("ARCHEION_GITHUB_RELEASE"), "Creating a GitHub release requires ARCHEION_GITHUB_RELEASE=1")?
			tag = match setting!("ARCHEION_VERSION") {
				"" => run!("git", ["describe", "--tags", "--abbrev=0", "--match", "preload-v*"])?
				value => "preload-${value}"
			}
			release = "${releases}/${tag}"
			_ = run!("sha256sum", ["--check", "--quiet", "--", "${release}/SHA256SUMS.txt"]) ? |_| Publish("${release} fails its SHA256SUMS.txt")
			repo = if setting!("ARCHEION_GITHUB_REPO") == "" "lyceum-quest/archeion" else setting!("ARCHEION_GITHUB_REPO")
			notes = "The Aristos preload (corpora, passages, and lemma index) built from `conllu/generated/` at this tag. Aristos pins it in `preload.lock.json`."
			_ = Cmd.new_str("gh").args_str(["release", "create", tag, "--repo", repo, "--verify-tag", "--title", "Aristos preload ${Str.drop_prefix(tag, "preload-")}", "--notes", notes, "--latest=false", "${release}/${asset}", "${release}/SHA256SUMS.txt"]).exec_cmd!()?
			Stdout.line!("Created the GitHub release ${tag} in ${repo}")
		}
		_ => Err(Publish("Usage: release-preload build|github"))
	}
}

require = |condition, message| if condition Ok({}) else Err(Publish(message))

# Per-run switches come only from the environment, never from .env, so a publication is always deliberate.
switch! = |name| (Env.var_str!(OsStr.from_str(name)) ?? "") == "1"

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Publish("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")
