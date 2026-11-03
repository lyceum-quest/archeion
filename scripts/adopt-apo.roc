app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.OsStr
import cli.Path
import cli.Stdout

# A stopgap until Archeion and apo settle on one format: continues a generated work (conllu/generated/<work>-<model>/,
# as scripts/generate/loop.roc writes it) with an apo output folder made from the same OGA text, starting at a later
# sentence. Sentences and passages from apo's first token on replace any already there, so it can run again after each
# apo session. apo writes no literal translations: its passages get an empty `literal`, and its sentences none.
# apo's output folder is copied to <work-folder>/apo/<first token>/ as the record of what made those sentences.
# Usage: roc scripts/adopt-apo.roc <apo-output-dir> <conllu/generated/work-model>
Unit : { label : Str, prose : Str, ref : Str, tokens : List(Str) }

main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[apo_dir, work_dir] => {
		read! = |path| Path.read_utf8!(Path.utf8(path)).map_ok(|text| Str.replace_each(text, "\r\n", "\n"))
		apo_output = read!("${apo_dir}/output.conllu")?
		apo_units = read!("${apo_dir}/units.jsonl")?
		work_output = read!("${work_dir}/output.conllu")?
		work_units = read!("${work_dir}/units.jsonl")?
		adopted = adopt(work_output, work_units, apo_output, apo_units)?
		Path.write_utf8!(Path.utf8("${work_dir}/output.conllu"), adopted.output)?
		Path.write_utf8!(Path.utf8("${work_dir}/units.jsonl"), adopted.units)?
		# One folder per apo session, named by the token it starts at, so a later session keeps an earlier one's record.
		session = "${work_dir}/apo/${adopted.first}"
		_ = Path.create_all!(Path.utf8(session))
		for name in ["output.conllu", "units.jsonl", "replies.jsonl"] {
			if Path.is_file!(Path.utf8("${apo_dir}/${name}")) ?? Bool.False {
				Path.write_utf8!(Path.utf8("${session}/${name}"), read!("${apo_dir}/${name}")?)?
			}
		}
		Stdout.line!("${work_dir}: ${U64.to_str(adopted.kept)} sentences kept, ${U64.to_str(adopted.added)} from apo (from ${adopted.first})")
	}
	_ => Err(Usage("adopt-apo.roc <apo-output-dir> <conllu/generated/work-model>"))
}

# Header comments apo writes once per file or per sentence that Archeion's works do not carry.
apo_only = ["# newdoc id", "# generator", "# model", "# config_sha256", "# sent_id"]

adopt = |work_output, work_units, apo_output, apo_units| {
	apo_blocks = blocks(apo_output)
	first = when_first(apo_blocks)?
	cut = token_number(first)?
	kept = List.keep_if(blocks(work_output), |block| before(block_token(block), cut))
	renumbered = List.map_with_index(apo_blocks, |block, i| renumber(block, List.len(kept) + i + 1))
	kept_units = List.keep_if(lines(work_units), |line| unit_before(line, cut))
	added_units = List.map_try(lines(apo_units), with_empty_literal)?
	Ok({
		# As loop.roc writes it: two blank lines between sentences, none after the last.
		output: "${Str.join_with(List.concat(kept, renumbered), "\n\n\n")}\n",
		units: Str.join_with(List.concat(kept_units, added_units) |> List.map(|l| "${l}\n"), ""),
		kept: List.len(kept),
		added: List.len(apo_blocks),
		first,
	})
}

when_first = |apo_blocks| match apo_blocks {
	[block, ..] => block_token(block)
	[] => Err(NoApoSentences)
}

blocks = |text| List.keep_if(List.map(Str.split_on(Str.trim(text), "\n\n"), Str.trim), |b| b != "")

lines = |text| List.keep_if(Str.split_on(text, "\n"), |l| Str.trim(l) != "")

# The first OGA token ID (`t_N`, the first MISC item) of a sentence's rows.
block_token = |block| {
	ids = List.keep_oks(
		Str.split_on(block, "\n"),
		|line| match Str.split_on(line, "\t") {
			[_, _, _, _, _, _, _, _, _, misc] =>
				match Str.split_on(misc, "|") {
					[id, ..] if Str.starts_with(id, "t_") => Ok(id)
					_ => Err(NotAToken)
				}
			_ => Err(NotARow)
		},
	)
	List.first(ids).map_err(|_| NoTokenInSentence(block))
}

token_number = |id| U64.from_str(Str.drop_prefix(id, "t_")).map_err(|_| BadTokenId(id))

# Whether a sentence or passage starting at this token comes before token number `cut`.
before = |token, cut| match token {
	Ok(id) => (token_number(id) ?? cut) < cut
	Err(_) => Bool.False
}

renumber = |block, index| {
	kept_lines = List.keep_if(Str.split_on(block, "\n"), |line| !List.any(apo_only, |prefix| Str.starts_with(line, prefix)))
	Str.join_with(List.map(kept_lines, |line| if Str.starts_with(line, "# sentence_id = ") "# sentence_id = ${U64.to_str(index)}" else line), "\n")
}

unit_before = |line, cut| {
	parsed : Try(Unit, _)
	parsed = Json.parse(line)
	match parsed {
		Ok(unit) => before(List.first(unit.tokens), cut)
		Err(_) => Bool.False
	}
}

with_empty_literal = |line| {
	unit : Unit
	unit = Json.parse(line)?
	Json.to_str_try({ label: unit.label, literal: "", prose: unit.prose, ref: unit.ref, tokens: unit.tokens })
}
