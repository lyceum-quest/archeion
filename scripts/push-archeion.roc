app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# Publishes a release that publish-archeion committed, tagged, and staged.
#   git:    pushes master and the release tag to each of ARCHEION_REMOTES (default `origin`).
#   github: creates the GitHub release from ARCHEION_RELEASE_DIR/<version>/, only for a production snapshot whose tag
#           is already on GitHub (push it to the GitHub remote first).
# The release is ARCHEION_VERSION, or else the newest v* tag.
# Usage: roc scripts/push-archeion.roc git|github
main! = |args| {
	archeion = "."
	version = match setting!("ARCHEION_VERSION") {
		"" => run!("git", ["-C", archeion, "describe", "--tags", "--abbrev=0", "--match", "v*"])?
		value => value
	}
	_ = run!("git", ["-C", archeion, "rev-parse", "--verify", "--quiet", "refs/tags/${version}"]) ? |_| Publish("no tag ${version}; run publish-archeion first")
	match args.map(OsStr.display) {
		[_, "git"] => {
			_ = require(switch!("ARCHEION_PUSH"), "Pushing requires ARCHEION_PUSH=1")?
			remotes = Str.split_on(if setting!("ARCHEION_REMOTES") == "" "origin" else setting!("ARCHEION_REMOTES"), " ").keep_if(|remote| remote != "")
			push!(archeion, version, remotes)
		}
		[_, "github"] => {
			_ = require(switch!("ARCHEION_GITHUB_RELEASE"), "Creating a GitHub release requires ARCHEION_GITHUB_RELEASE=1")?
			release = "${if setting!("ARCHEION_RELEASE_DIR") == "" "/var/tmp/archeion-releases" else setting!("ARCHEION_RELEASE_DIR")}/${version}"
			manifest : { version : Str, verified_against : { target : Str } }
			manifest = Json.parse(Path.read_utf8!(Path.utf8("${release}/manifest.json"))?)?
			_ = require(manifest.version == version, "${release}/manifest.json is for ${manifest.version}")?
			_ = require(manifest.verified_against.target == "production", "${version} was verified against ${manifest.verified_against.target}; only a production snapshot becomes a GitHub release")?
			repo = if setting!("ARCHEION_GITHUB_REPO") == "" "lyceum-quest/archeion" else setting!("ARCHEION_GITHUB_REPO")
			sums = Str.split_on(Path.read_utf8!(Path.utf8("${release}/SHA256SUMS.txt"))?, "\n").keep_if(|line| Str.trim(line) != "")
			_ = run!("env", ["--chdir", release, "sha256sum", "--check", "--quiet", "--", "SHA256SUMS.txt"]) ? |_| Publish("${release} fails its SHA256SUMS.txt")
			assets = List.append(sums.map(|line| "${release}/${List.last(Str.split_on(line, " ")) ?? ""}"), "${release}/SHA256SUMS.txt")
			_ = gh!(repo, List.concat(["release", "create", version, "--repo", repo, "--verify-tag", "--title", version, "--notes-file", "${release}/NOTES.md"], assets))?
			Stdout.line!("Created the GitHub release ${version} in ${repo}")
		}
		_ => Err(Publish("Usage: push-archeion git|github"))
	}
}

push! = |archeion, version, remotes| match remotes {
	[] => Ok({})
	[remote, .. as rest] => {
		_ = Cmd.new_str("git").args_str(["-C", archeion, "push", remote, "master", "refs/tags/${version}"]).exec_cmd!()?
		_ = Stdout.line!("Pushed master and ${version} to ${remote}")?
		push!(archeion, version, rest)
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

# gh as the repository's owner: with ~/.config/github-tokens/<owner> (the token git pushes with, through blu-dev's
# credential helper), gh runs with it as GH_TOKEN; the personal gh login can't reach organisation repositories.
gh! = |repo, args| {
	owner = match Str.split_first(repo, "/") {
		Ok({ before, after: _ }) => before
		Err(_) => repo
	}
	home = Env.var_str!(OsStr.from_str("HOME")) ?? ""
	token = Str.trim(Path.read_utf8!(Path.utf8("${home}/.config/github-tokens/${owner}")) ?? "")
	cmd = Cmd.new_str("gh").args_str(args)
	# The error names gh's arguments only: Cmd's own error text would print the environment, token included.
	result = if token == "" cmd.exec_cmd!() else cmd.env_str("GH_TOKEN", token).exec_cmd!()
	match result {
		Ok(_) => Ok({})
		Err(_) => Err(GitHub("gh ${Str.join_with(args.take_first(2), " ")} failed (its output is above)"))
	}
}
