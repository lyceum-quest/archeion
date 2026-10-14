app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# Packs an app's preload as a release the app pins and fetches; the apps generate no data.
#   aristos:    corpora.json, corpora/, and lemmas.json (see build-corpus-preload.roc) built from the committed
#               conllu/generated/, as preload-<version>/aristos-preload.tar.zst, pinned in Aristos's preload.lock.json.
#   conllu-viz: conllu/conllu-viz.json (as conllu-files.json) and the treebanks it lists, in the layout it serves under
#               /preload/, as conllu-viz-<version>/conllu-viz-preload.tar.gz, pinned in conllu-viz's data.lock.json.
# build writes the archive (reproducible: sorted, zero mtimes and owners) and SHA256SUMS.txt to
# ARCHEION_RELEASE_DIR/<tag>/ and tags HEAD; nothing leaves this machine. github creates the GitHub release from them;
# it needs ARCHEION_GITHUB_RELEASE=1 and the tag on GitHub (push it first).
# The version is ARCHEION_VERSION, or else today's vYYYY.MM.DD when building and the app's newest tag otherwise.
# Usage: roc scripts/release-preload.roc build|github aristos|conllu-viz
Kind : { target : Str, prefix : Str, asset : Str, compress : Str, sources : List(Str), title : Str, notes : Str }

kind = |target| match target {
	"aristos" => Ok({ target, prefix: "preload-", asset: "aristos-preload.tar.zst", compress: "zstd -19 -T1", sources: ["conllu/generated", "data/oga", "scripts"], title: "Aristos preload", notes: "The Aristos preload (corpora, passages, and lemma index) built from `conllu/generated/` at this tag. Aristos pins it in `preload.lock.json`." })
	"conllu-viz" => Ok({ target, prefix: "conllu-viz-", asset: "conllu-viz-preload.tar.gz", compress: "gzip -n -9", sources: ["conllu"], title: "CoNLL-U visualizer preload", notes: "The treebanks the CoNLL-U visualizer preloads, with their manifest (`conllu/conllu-viz.json` at this tag, as `conllu-files.json`). conllu-viz pins it in `data.lock.json`." })
	_ => Err(Publish("Usage: release-preload build|github aristos|conllu-viz"))
}

main! = |args| {
	releases = if setting!("ARCHEION_RELEASE_DIR") == "" "/var/tmp/archeion-releases" else setting!("ARCHEION_RELEASE_DIR")
	match args.map(OsStr.display) {
		[_, "build", target] => {
			preload = kind(target)?
			version = match setting!("ARCHEION_VERSION") {
				"" => run!("date", ["-u", "+v%Y.%m.%d"])?
				value => value
			}
			tag = "${preload.prefix}${version}"
			release = "${releases}/${tag}"
			_ = require(run!("git", List.concat(["status", "--porcelain", "--"], preload.sources))? == "", "${Str.join_with(preload.sources, ", ")} has uncommitted changes")?
			_ = match run!("git", ["rev-parse", "--verify", "--quiet", "refs/tags/${tag}"]) {
				Ok(_) => Err(Publish("tag ${tag} already exists; set ARCHEION_VERSION"))
				Err(_) => Ok({})
			}?
			_ = require(!(Path.exists!(Path.utf8(release)) ?? Bool.False), "${release} already exists")?
			scratch = run!("mktemp", ["-d", "/tmp/archeion-preload.XXXXXXXXXX"])?
			members = stage!(target, "${scratch}/preload")?
			_ = run!("mkdir", ["-p", "--", release])?
			_ = run!("tar", List.concat(["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "--use-compress-program=${preload.compress}", "-C", "${scratch}/preload", "-cf", "${release}/${preload.asset}"], members))?
			_ = run!("rm", ["-rf", "--", scratch])?
			sum = run!("sha256sum", ["--", "${release}/${preload.asset}"])?
			_ = Path.write_utf8!(Path.utf8("${release}/SHA256SUMS.txt"), "${Str.replace_each(sum, "${release}/", "")}\n")?
			_ = run!("git", ["tag", "--annotate", tag, "--message", "${preload.title} ${version}"])?
			Stdout.line!("Tagged ${tag}; ${release}/${preload.asset} is ${List.first(Str.split_on(sum, " ")) ?? ""}. Push the tag, then create the GitHub release.")
		}
		[_, "github", target] => {
			preload = kind(target)?
			_ = require(switch!("ARCHEION_GITHUB_RELEASE"), "Creating a GitHub release requires ARCHEION_GITHUB_RELEASE=1")?
			tag = match setting!("ARCHEION_VERSION") {
				"" => run!("git", ["describe", "--tags", "--abbrev=0", "--match", "${preload.prefix}v*"])?
				value => "${preload.prefix}${value}"
			}
			release = "${releases}/${tag}"
			_ = run!("env", ["--chdir", release, "sha256sum", "--check", "--quiet", "--", "SHA256SUMS.txt"]) ? |_| Publish("${release} fails its SHA256SUMS.txt")
			repo = if setting!("ARCHEION_GITHUB_REPO") == "" "lyceum-quest/archeion" else setting!("ARCHEION_GITHUB_REPO")
			_ = Cmd.new_str("gh").args_str(["release", "create", tag, "--repo", repo, "--verify-tag", "--title", "${preload.title} ${Str.drop_prefix(tag, preload.prefix)}", "--notes", preload.notes, "--latest=false", "${release}/${preload.asset}", "${release}/SHA256SUMS.txt"]).exec_cmd!()?
			Stdout.line!("Created the GitHub release ${tag} in ${repo}")
		}
		_ => Err(Publish("Usage: release-preload build|github aristos|conllu-viz"))
	}
}

# Writes the target's preload to `dir` and returns the paths to archive, relative to it.
stage! = |target, dir| match target {
	"aristos" => {
		_ = Cmd.new_str("roc").args_str(["scripts/build-corpus-preload.roc", dir, "conllu/generated"]).exec_cmd!()?
		Ok(["corpora.json", "corpora", "lemmas.json"])
	}
	_ => {
		manifest : { files : List({ path : Str }) }
		manifest = Json.parse(Path.read_utf8!(Path.utf8("conllu/conllu-viz.json"))?)?
		files = manifest.files.map(|file| Str.drop_prefix(file.path, "/preload/"))
		_ = require(List.all(manifest.files, |file| Str.starts_with(file.path, "/preload/") and !Str.contains(file.path, "..")), "conllu/conllu-viz.json lists a path outside /preload/")?
		_ = run!("mkdir", ["-p", "--", dir])?
		_ = run!("cp", ["--", "conllu/conllu-viz.json", "${dir}/conllu-files.json"])?
		_ = copy!(files, dir)?
		Ok(List.prepend(files, "conllu-files.json"))
	}
}

copy! = |files, dir| match files {
	[] => Ok({})
	[file, .. as rest] => {
		_ = run!("install", ["-D", "-m", "644", "--", "conllu/${file}", "${dir}/${file}"])?
		copy!(rest, dir)
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
