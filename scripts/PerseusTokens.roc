# Perseus's token sidecars (one `<chunk>.tokens.json` per citation chunk; see data/perseus/README.md) as CoNLL-U for apo,
# in the shape OGA gives it: sentences whose first MISC item is each token's ID, and `<token ID><TAB><citation>` rows.
# Values stay as Perseus has them (UD style); `null` is written `_`. Anything outside sidecar schema 2 fails.
#
# Sentences never cross a chunk. When every word of a chunk has a relation (a dependency parse), each tree is a
# sentence; otherwise a sentence ends after a terminator (`terminators`) and any punctuation that follows it without a
# space. A parse arriving can therefore move sentence boundaries and `# sent_id`s, never token IDs or citations.
PerseusTokens :: [].{

	Word : {
		id : U64,
		text : Str,
		lemma : Try(Str, [Null]),
		upos : Try(Str, [Null]),
		xpos : Try(Str, [Null]),
		feats : Try(Str, [Null]),
		head : Try(U64, [Null]),
		deprel : Try(Str, [Null]),
		deps : Try(Str, [Null]),
		misc : Try(Str, [Null]),
	}

	Token : {
		text : Str,
		start_char : U64,
		end_char : U64,
		whitespace : Bool,
		id : List(U64),
		ner : Try(Str, [Null]),
		misc : Try(Str, [Null]),
		identifier : Str,
		urn : Try(Str, [Null]),
		words : List(Word),
	}

	Chunk : { urn : Str, lang : Str, tokens : List(Token) }

	Converted : { sentences : List(Str), refs : List(Str) }

	# The pipeline a sidecar comes from (tokens-manifest.json): only schema 2 with a full spaCy analysis (lemmas, tags,
	# features) is read; tokenize-only sidecars have no annotation to give.
	check_pipeline : Str -> Try({}, [Unexpected(Str), ..])
	check_pipeline = |pipeline|
		if Str.starts_with(pipeline, "2:spacy-") and Str.ends_with(pipeline, ":analyze") {
			Ok({})
		} else {
			Err(Unexpected("pipeline ${pipeline}, not sidecar schema 2 from a spaCy analysis"))
		}

	# Sentence-final punctuation tokens by language.
	terminators : Str -> Try(List(Str), [Unexpected(Str), ..])
	terminators = |lang| match lang {
		"grc" => Ok([".", ";", "\u(37e)", "\u(b7)", "\u(387)"])
		"la" => Ok([".", ";", "?", "!"])
		other => Err(Unexpected("language ${other}"))
	}

	convert : Chunk -> Try(Converted, [Unexpected(Str), ..])
	convert = |chunk| {
		ref = Str.replace_each(passage(chunk.urn)?, ".", "_")
		check_tokens(chunk)?
		words = List.join(List.map(chunk.tokens, |token| token.words))
		parsed = List.all(words, |word| word.deprel != Err(Null))
		groups = if parsed trees(chunk.tokens, words)? else punctuated(chunk.tokens, terminators(chunk.lang)?)
		written = List.sum(List.map(groups, List.len))
		if written != List.len(chunk.tokens) {
			return Err(Unexpected("${chunk.urn}: ${U64.to_str(written)} of ${U64.to_str(List.len(chunk.tokens))} tokens written"))
		}
		sentences = List.map_try(List.map_with_index(groups, |group, i| (group, i)), |(group, i)| sentence(chunk.urn, i + 1, group, parsed))?
		refs = List.map(chunk.tokens, |token| "${token_id(chunk.urn, token)}\t${ref}")
		Ok({ sentences, refs })
	}

	# `urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1` -> `1.1`
	passage : Str -> Try(Str, [Unexpected(Str), ..])
	passage = |urn| match Str.split_on(urn, ":") {
		["urn", "cts", _, _, cited] if cited != "" => Ok(cited)
		_ => Err(Unexpected("chunk URN ${urn} has no passage"))
	}

	# Perseus gives punctuation no URN; its ID is built the same way, from its identifier (`,[2]`).
	token_id : Str, Token -> Str
	token_id = |chunk_urn, token| token.urn ?? "${chunk_urn}@${token.identifier}"

	check_tokens : Chunk -> Try({}, [Unexpected(Str), ..])
	check_tokens = |chunk| {
		ids = List.join(List.map(chunk.tokens, |token| List.map(token.words, |word| word.id)))
		increasing = List.all(List.map_with_index(ids, |id, i| (id, i)), |(id, i)| i == 0 or (List.get(ids, i - 1) ?? id) < id)
		if !increasing {
			return Err(Unexpected("${chunk.urn}: word ids are not increasing"))
		}
		List.fold_try(chunk.tokens, {}, |{}, token| check_token(chunk.urn, token))
	}

	check_token : Str, Token -> Try({}, [Unexpected(Str), ..])
	check_token = |chunk_urn, token| {
		at = "${chunk_urn}@${token.identifier}"
		urn_ok = match token.urn {
			Ok(urn) => urn == at
			Err(Null) => Bool.True
		}
		problem =
			if token.text == "" or List.is_empty(token.words) {
				Ok("an empty token")
			} else if token.id != List.map(token.words, |word| word.id) {
				Ok("token ids that are not its words' ids")
			} else if !urn_ok {
				Ok("a URN that is not its chunk's URN @ its identifier")
			} else if token.ner != Err(Null) or token.misc != Err(Null) {
				Ok("a named entity or MISC")
			} else if List.any(token.words, |word| word.deps != Err(Null) or word.misc != Err(Null)) {
				Ok("a word with DEPS or MISC")
			} else if Str.contains(token_id(chunk_urn, token), "|") {
				Ok("an ID that cannot be a MISC item")
			} else {
				Err(None)
			}
		match problem {
			Ok(what) => Err(Unexpected("${at}: ${what}"))
			Err(None) => Ok({})
		}
	}

	# A sentence ends after a terminator and any punctuation attached to it (`.”`).
	punctuated : List(Token), List(Str) -> List(List(Token))
	punctuated = |tokens, ends| {
		step = List.fold(
			tokens,
			{ done: [], open: [], ending: Bool.False },
			|state, token| {
				punct = token.urn == Err(Null)
				attached = match List.last(state.open) {
					Ok(previous) => !previous.whitespace
					Err(_) => Bool.False
				}
				if state.ending and !(punct and attached) {
					{ done: List.append(state.done, state.open), open: [token], ending: List.contains(ends, token.text) }
				} else {
					{ done: state.done, open: List.append(state.open, token), ending: state.ending or List.contains(ends, token.text) }
				}
			},
		)
		if List.is_empty(step.open) step.done else List.append(step.done, step.open)
	}

	# One sentence per dependency tree; a tree must be a contiguous run of tokens.
	trees : List(Token), List(Word) -> Try(List(List(Token)), [Unexpected(Str), ..])
	trees = |tokens, words| {
		heads = Dict.from_list(List.map(words, |word| (word.id, word.head)))
		root = |id| climb(heads, id, List.len(words))
		keyed = List.map_try(
			tokens,
			|token| {
				roots = List.map_try(token.words, |word| root(word.id))?
				match roots {
					[first, .. as rest] if List.all(rest, |r| r == first) => Ok((first, token))
					_ => Err(Unexpected("${token.identifier}: a token's words in different trees"))
				}
			},
		)?
		step = List.fold_try(
			keyed,
			{ done: [], open: [], key: None, seen: [] },
			|state, (key, token)| {
				if state.key == Some(key) {
					Ok({ ..state, open: List.append(state.open, token) })
				} else if List.contains(state.seen, key) {
					Err(Unexpected("${token.identifier}: a tree that is not contiguous"))
				} else {
					done = if List.is_empty(state.open) state.done else List.append(state.done, state.open)
					Ok({ done, open: [token], key: Some(key), seen: List.append(state.seen, key) })
				}
			},
		)?
		Ok(if List.is_empty(step.open) step.done else List.append(step.done, step.open))
	}

	climb : Dict(U64, Try(U64, [Null])), U64, U64 -> Try(U64, [Unexpected(Str), ..])
	climb = |heads, id, steps| match Dict.get(heads, id) {
		Ok(Err(Null)) => Ok(id)
		Ok(Ok(head)) => if steps == 0 Err(Unexpected("word ${U64.to_str(id)}: heads that form a cycle")) else climb(heads, head, steps - 1)
		Err(_) => Err(Unexpected("word ${U64.to_str(id)}: a head that is no word of the chunk"))
	}

	sentence : Str, U64, List(Token), Bool -> Try(Str, [Unexpected(Str), ..])
	sentence = |chunk_urn, n, tokens, parsed| {
		words = List.join(List.map(tokens, |token| token.words))
		numbers = Dict.from_list(List.map_with_index(words, |word, i| (word.id, i + 1)))
		rows = List.join(List.map_try(tokens, |token| token_rows(chunk_urn, numbers, parsed, token))?)
		text = Str.join_with(List.map_with_index(tokens, |token, i| if token.whitespace and i + 1 < List.len(tokens) "${token.text} " else token.text), "")
		Ok(Str.join_with(List.concat(["# sent_id = ${chunk_urn}.${U64.to_str(n)}", "# text = ${text}"], rows), "\n"))
	}

	token_rows : Str, Dict(U64, U64), Bool, Token -> Try(List(Str), [Unexpected(Str), ..])
	token_rows = |chunk_urn, numbers, parsed, token| {
		misc = Str.join_with(
			List.concat(
				[token_id(chunk_urn, token)],
				List.concat(if token.whitespace [] else ["SpaceAfter=No"], ["TokenRange=${U64.to_str(token.start_char)}:${U64.to_str(token.end_char)}"]),
			),
			"|",
		)
		number = |word| Dict.get(numbers, word.id) ?? 0
		match token.words {
			[word] => Ok([row(number(word), field(token.text)?, word, numbers, parsed, misc)?])
			[first, ..] => {
				last = List.last(token.words) ?? first
				range = "${U64.to_str(number(first))}-${U64.to_str(number(last))}\t${field(token.text)?}\t_\t_\t_\t_\t_\t_\t_\t${misc}"
				words = List.map_try(token.words, |word| row(number(word), field(word.text)?, word, numbers, parsed, "_"))?
				Ok(List.prepend(words, range))
			}
			[] => Err(Unexpected("${token.identifier}: no words"))
		}
	}

	row : U64, Str, Word, Dict(U64, U64), Bool, Str -> Try(Str, [Unexpected(Str), ..])
	row = |n, form, word, numbers, parsed, misc| {
		head = match word.head {
			Err(Null) => if parsed "0" else "_"
			Ok(id) => match Dict.get(numbers, id) {
				Ok(number) => U64.to_str(number)
				Err(_) => return Err(Unexpected("${word.text} (word ${U64.to_str(word.id)}): a head outside its sentence"))
			}
		}
		columns = List.map_try([word.lemma, word.upos, word.xpos, word.feats], nullable)?
		deprel = nullable(word.deprel)?
		Ok(Str.join_with(List.concat(List.concat([U64.to_str(n), form], columns), [head, deprel, "_", misc]), "\t"))
	}

	nullable : Try(Str, [Null]) -> Try(Str, [Unexpected(Str), ..])
	nullable = |value| match value {
		Ok(text) => field(text)
		Err(Null) => Ok("_")
	}

	# A column value: never empty, and with no tab or line break.
	field : Str -> Try(Str, [Unexpected(Str), ..])
	field = |text|
		if text == "" or Str.contains(text, "\t") or Str.contains(text, "\n") or Str.contains(text, "\r") {
			Err(Unexpected("the value \"${text}\""))
		} else {
			Ok(text)
		}
}

word = |id, text, head, deprel| { id, text, lemma: Ok(text), upos: Ok("X"), xpos: Err(Null), feats: Err(Null), head, deprel, deps: Err(Null), misc: Err(Null) }

token = |id, text, whitespace, head, deprel| {
	text,
	start_char: id * 10,
	end_char: id * 10 + Str.count_utf8_bytes(text),
	whitespace,
	id: [id],
	ner: Err(Null),
	misc: Err(Null),
	identifier: "${text}[1]",
	urn: if text == "." or text == "”" Err(Null) else Ok("urn:cts:latinLit:x.y.z:1@${text}[1]"),
	words: [word(id, text, head, deprel)],
}

texts = |converted| List.map(converted.sentences, |s| List.keep_if(Str.split_on(s, "\n"), |line| !Str.starts_with(line, "#")))

# Unparsed: a sentence ends after `.` and the quote attached to it; heads that exist are made sentence-relative.
expect {
	chunk = { urn: "urn:cts:latinLit:x.y.z:1", lang: "la", tokens: [token(0, "a", Bool.False, Err(Null), Err(Null)), token(1, "que", Bool.True, Ok(0), Ok("cc")), token(2, "b", Bool.False, Err(Null), Err(Null)), token(3, ".", Bool.False, Err(Null), Err(Null)), token(4, "”", Bool.True, Err(Null), Err(Null)), token(5, "c", Bool.True, Err(Null), Err(Null)), token(6, "d", Bool.False, Ok(5), Ok("cc"))] }
	match PerseusTokens.convert(chunk) {
		Ok(converted) =>
			texts(converted)
				== [
					[
						"1\ta\ta\tX\t_\t_\t_\t_\t_\turn:cts:latinLit:x.y.z:1@a[1]|SpaceAfter=No|TokenRange=0:1",
						"2\tque\tque\tX\t_\t_\t1\tcc\t_\turn:cts:latinLit:x.y.z:1@que[1]|TokenRange=10:13",
						"3\tb\tb\tX\t_\t_\t_\t_\t_\turn:cts:latinLit:x.y.z:1@b[1]|SpaceAfter=No|TokenRange=20:21",
						"4\t.\t.\tX\t_\t_\t_\t_\t_\turn:cts:latinLit:x.y.z:1@.[1]|SpaceAfter=No|TokenRange=30:31",
						"5\t”\t”\tX\t_\t_\t_\t_\t_\turn:cts:latinLit:x.y.z:1@”[1]|TokenRange=40:43",
					],
					[
						"1\tc\tc\tX\t_\t_\t_\t_\t_\turn:cts:latinLit:x.y.z:1@c[1]|TokenRange=50:51",
						"2\td\td\tX\t_\t_\t1\tcc\t_\turn:cts:latinLit:x.y.z:1@d[1]|SpaceAfter=No|TokenRange=60:61",
					],
				]
				and List.map(converted.sentences, |s| List.take_first(Str.split_on(s, "\n"), 2))
					== [["# sent_id = urn:cts:latinLit:x.y.z:1.1", "# text = aque b.”"], ["# sent_id = urn:cts:latinLit:x.y.z:1.2", "# text = c d"]]
					and List.len(converted.refs) == 7
						and List.first(converted.refs) == Ok("urn:cts:latinLit:x.y.z:1@a[1]\t1")
		Err(_) => Bool.False
	}
}

# Parsed: each tree is a sentence whatever the punctuation, its root's head is 0.
expect {
	chunk = { urn: "urn:cts:latinLit:x.y.z:1", lang: "la", tokens: [token(0, "a", Bool.True, Ok(1), Ok("nsubj")), token(1, "b", Bool.False, Err(Null), Ok("ROOT")), token(2, ".", Bool.True, Ok(1), Ok("punct")), token(3, "c", Bool.True, Err(Null), Ok("ROOT")), token(4, "d", Bool.True, Ok(3), Ok("obj"))] }
	match PerseusTokens.convert(chunk) {
		Ok(converted) =>
			List.map(texts(converted), |rows| List.map(rows, |r| List.take_first(Str.split_on(r, "\t"), 8)))
				== [
					[["1", "a", "a", "X", "_", "_", "2", "nsubj"], ["2", "b", "b", "X", "_", "_", "0", "ROOT"], ["3", ".", ".", "X", "_", "_", "2", "punct"]],
					[["1", "c", "c", "X", "_", "_", "0", "ROOT"], ["2", "d", "d", "X", "_", "_", "1", "obj"]],
				]
		Err(_) => Bool.False
	}
}

# A tree split by another fails rather than reorder the text.
expect {
	chunk = { urn: "urn:cts:latinLit:x.y.z:1", lang: "la", tokens: [token(0, "a", Bool.True, Err(Null), Ok("ROOT")), token(1, "b", Bool.True, Err(Null), Ok("ROOT")), token(2, "c", Bool.True, Ok(0), Ok("obj"))] }
	PerseusTokens.convert(chunk) == Err(Unexpected("c[1]: a tree that is not contiguous"))
}

# An unparsed head that crosses a sentence boundary fails.
expect {
	chunk = { urn: "urn:cts:latinLit:x.y.z:1", lang: "la", tokens: [token(0, "a", Bool.False, Err(Null), Err(Null)), token(1, ".", Bool.True, Err(Null), Err(Null)), token(2, "b", Bool.True, Ok(0), Ok("cc"))] }
	PerseusTokens.convert(chunk) == Err(Unexpected("b (word 2): a head outside its sentence"))
}

expect PerseusTokens.check_pipeline("2:spacy-3.8.15:grc_dep_web_lg-3.8.2:analyze") == Ok({})

expect PerseusTokens.check_pipeline("2:stanza-1.10.1:tokenize") != Ok({})

expect PerseusTokens.check_pipeline("3:spacy-3.8.15:grc_dep_web_lg-3.8.2:analyze") != Ok({})
