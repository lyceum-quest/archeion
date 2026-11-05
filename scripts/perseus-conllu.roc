app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite
import PerseusTokens

# Perseus's annotated texts as apo input, in the shape OGA's are: <out-dir>/<work>.conllu and <work>.refs.tsv (see
# scripts/PerseusTokens.roc and data/perseus/README.md).
#   convert <corpus> <work-urn> <out-dir> [<chunk-count>]
#       Fetches the corpus's archive as pinned in data/perseus/pins.tsv into ARCHEION_PERSEUS_CACHE (default
#       /var/tmp/archeion-perseus) unless it is there, checks its digest, unpacks the work once, and converts its first
#       <chunk-count> chunks (default all) in citation order (index.json).
#   convert-dir <work-dir> <work-urn> <out-dir> [<chunk-count>]
#       The same from an unpacked work whose chunks are already decompressed (<chunk>.tokens.json), as in the tests.
#   pin <corpus>
#       Pins the corpus's current `latest` image in data/perseus/pins.tsv.
# Usage: roc scripts/perseus-conllu.roc convert|convert-dir|pin ...
Pin : { corpus : Str, image : Str, digest : Str, size : Str, created : Str }

pins_path = "data/perseus/pins.tsv"

media_type = "application/vnd.perseus.mvp.tokens"

complete = ".archeion-unpacked"

main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	["convert", corpus, urn, out, .. as count] => {
		pin = find_pin(Path.read_utf8!(Path.utf8(pins_path))?, corpus)?
		dir = unpack!(pin, work_path(urn)?)?
		write!(dir, urn, out, count)
	}
	["convert-dir", dir, urn, out, .. as count] => write!(dir, urn, out, count)
	["pin", corpus] => pin!(corpus)
	_ => Err(Usage("perseus-conllu.roc convert <corpus> <work-urn> <out-dir> [<chunk-count>] | convert-dir <work-dir> <work-urn> <out-dir> [<chunk-count>] | pin <corpus>"))
}

# `urn:cts:greekLit:tlg0012.tlg001.perseus-grc2` -> `greekLit/tlg0012/tlg001/perseus-grc2`, the work's folder in its
# corpus archive.
work_path = |urn| match Str.split_on(urn, ":") {
	["urn", "cts", namespace, work] =>
		match Str.split_on(work, ".") {
			[group, text, edition] => Ok("${namespace}/${group}/${text}/${edition}")
			_ => Err(Perseus("${urn} is not a work URN (textgroup.work.edition)"))
		}
	_ => Err(Perseus("${urn} is not a work URN (urn:cts:<namespace>:<textgroup>.<work>.<edition>)"))
}

write! = |dir, urn, out, count| {
	name = List.last(Str.split_on(urn, ":")) ?? urn
	index : { chunks : List({ file : Str, cts_urn : Str }) }
	index = Json.parse(Path.read_utf8!(Path.utf8("${dir}/index.json"))?)?
	manifest : { chunks : Dict(Str, { lang : Str, pipeline : Str }) }
	manifest = Json.parse(Path.read_utf8!(Path.utf8("${dir}/tokens-manifest.json"))?)?
	chunks = match count {
		[] => index.chunks
		[n] => List.take_first(index.chunks, U64.from_str(n) ? |_| Perseus("${n} is not a chunk count"))
		_ => return Err(Usage("one chunk count at most"))
	}
	var $sentences = []
	var $refs = []
	var $tokens = 0
	for entry in chunks {
		converted = convert_chunk!(dir, urn, manifest.chunks, entry) ? |err| Perseus("${entry.file}: ${message(err)}")
		$sentences = List.concat($sentences, converted.sentences)
		$refs = List.concat($refs, converted.refs)
		$tokens = $tokens + List.len(converted.refs)
	}
	_ = Path.create_all!(Path.utf8(out))
	Path.write_utf8!(Path.utf8("${out}/${name}.conllu"), Str.join_with(List.map($sentences, |s| "${s}\n\n"), ""))?
	Path.write_utf8!(Path.utf8("${out}/${name}.refs.tsv"), Str.join_with(List.map($refs, |r| "${r}\n"), ""))?
	Stdout.line!("${out}/${name}.conllu: ${U64.to_str(List.len(chunks))} chunks, ${U64.to_str(List.len($sentences))} sentences, ${U64.to_str($tokens)} tokens")
}

convert_chunk! = |dir, urn, manifest, entry| {
	described = Dict.get(manifest, entry.file) ? |_| Unexpected("not in tokens-manifest.json")
	PerseusTokens.check_pipeline(described.pipeline)?
	if !Str.starts_with(entry.cts_urn, "${urn}:") {
		return Err(Unexpected("${entry.cts_urn} is not a passage of ${urn}"))
	}
	chunk : PerseusTokens.Chunk
	chunk = Json.parse(Path.read_utf8!(Path.utf8("${dir}/${Str.drop_suffix(entry.file, ".xml")}.tokens.json"))?)?
	if chunk.urn != entry.cts_urn or chunk.lang != described.lang {
		return Err(Unexpected("${chunk.urn} (${chunk.lang}) where index.json and tokens-manifest.json have ${entry.cts_urn} (${described.lang})"))
	}
	PerseusTokens.convert(chunk)
}

message = |err| match err {
	Unexpected(text) => "unexpected ${text}"
	other => Str.inspect(other)
}

# The work's folder, unpacked once from the pinned archive: tar extracts just the work, and one zstd run decompresses
# all its chunks.
unpack! = |pin, path| {
	cache = if setting!("ARCHEION_PERSEUS_CACHE") == "" "/var/tmp/archeion-perseus" else setting!("ARCHEION_PERSEUS_CACHE")
	hex = Str.drop_prefix(pin.digest, "sha256:")
	archive = "${cache}/${pin.corpus}-${hex}.tar.zst"
	root = "${cache}/${pin.corpus}-${hex}"
	dir = "${root}/${path}"
	if Path.exists!(Path.utf8("${dir}/${complete}")) ?? Bool.False {
		return Ok(dir)
	}
	_ = Path.create_all!(Path.utf8(root))
	if !(Path.exists!(Path.utf8(archive)) ?? Bool.False) {
		fetch!(pin, archive)?
	}
	verify!(archive, pin)?
	Stdout.line!("unpacking ${path} from ${archive}")?
	exec!("tar", ["--zstd", "-xf", archive, "-C", root, "./${path}"]) ? |_| Perseus("could not unpack ${path} from ${archive}; is the work in ${pin.corpus}?")
	compressed = List.keep_if(List.map(Path.list!(Path.utf8(dir))?, Path.display), |file| Str.ends_with(file, ".tokens.json.zst"))
	if List.is_empty(compressed) {
		return Err(Perseus("${dir} has no chunks"))
	}
	exec!("zstd", List.concat(["-d", "-q", "-f", "--"], compressed))?
	Path.write_utf8!(Path.utf8("${dir}/${complete}"), "${pin.digest}\n")?
	Ok(dir)
}

fetch! = |pin, archive| {
	repository = Str.drop_prefix(pin.image, "ghcr.io/")
	token = registry_token!(repository)?
	Stdout.line!("fetching ${pin.image}@${pin.digest} (${pin.size} bytes)")?
	exec!("curl", ["-fsSL", "--retry", "3", "-H", "Authorization: Bearer ${token}", "-o", "${archive}.part", "https://ghcr.io/v2/${repository}/blobs/${pin.digest}"])?
	verify!("${archive}.part", pin)?
	exec!("mv", ["--", "${archive}.part", archive])
}

verify! = |file, pin| {
	sum = output!("sha256sum", ["--", file])?
	if "sha256:${List.first(Str.split_on(sum, " ")) ?? ""}" == pin.digest {
		Ok({})
	} else {
		Err(Perseus("${file} does not have the pinned digest ${pin.digest}"))
	}
}

# Anonymous pull access to a public GitHub Container Registry repository.
registry_token! = |repository| {
	reply : { token : Str }
	reply = Json.parse(output!("curl", ["-fsS", "https://ghcr.io/token?scope=repository:${repository}:pull"])?)?
	Ok(reply.token)
}

pin! = |corpus| {
	image = "ghcr.io/perseusdlcode/mvp-tokens-${corpus}"
	repository = Str.drop_prefix(image, "ghcr.io/")
	token = registry_token!(repository)?
	manifest : { layers : List({ mediaType : Str, digest : Str, size : U64 }), annotations : Dict(Str, Str) }
	manifest = Json.parse(output!("curl", ["-fsS", "-H", "Authorization: Bearer ${token}", "-H", "Accept: application/vnd.oci.image.manifest.v1+json", "https://ghcr.io/v2/${repository}/manifests/latest"])?)?
	layer = match manifest.layers {
		[only] if only.mediaType == media_type => only
		_ => return Err(Perseus("${image}:latest is not one ${media_type} layer"))
	}
	created = Dict.get(manifest.annotations, "org.opencontainers.image.created") ?? ""
	pin = { corpus, image, digest: layer.digest, size: U64.to_str(layer.size), created }
	pins = Path.read_utf8!(Path.utf8(pins_path))?
	Path.write_utf8!(Path.utf8(pins_path), with_pin(pins, pin))?
	Stdout.line!("${corpus}: pinned ${pin.digest} (${pin.created})")
}

# data/perseus/pins.tsv: `#` comments, then `corpus<TAB>image<TAB>digest<TAB>size<TAB>created` rows.
parse_pin = |line| match Str.split_on(line, "\t") {
	[corpus, image, digest, size, created] => Ok({ corpus, image, digest, size, created })
	_ => Err(NotAPin)
}

find_pin = |pins, corpus| {
	rows = List.keep_oks(Str.split_on(pins, "\n"), |line| if Str.starts_with(line, "#") Err(Comment) else parse_pin(line))
	List.first(List.keep_if(rows, |pin| pin.corpus == corpus)).map_err(|_| Perseus("${corpus} is not pinned in ${pins_path}"))
}

with_pin = |pins, pin| {
	line = Str.join_with([pin.corpus, pin.image, pin.digest, pin.size, pin.created], "\t")
	lines = List.keep_if(Str.split_on(pins, "\n"), |l| l != "")
	known = List.any(lines, |l| Str.starts_with(l, "${pin.corpus}\t"))
	kept = List.map(lines, |l| if Str.starts_with(l, "${pin.corpus}\t") line else l)
	"${Str.join_with(if known kept else List.append(kept, line), "\n")}\n"
}

exec! = |program, args| Cmd.new_str(program).args_str(args).exec_cmd!().map_err(|_| Perseus("${program} failed"))

output! = |program, args| {
	result = Cmd.new_str(program).args_str(args).exec_output!() ? |_| Perseus("${program} failed")
	Ok(Str.trim(result.stdout_utf8))
}

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")
