# Perseus token annotation

The Perseus Digital Library (Tufts) annotates its corpora nightly: every citation chunk of every edition gets a lemma,
UD part of speech, XPOS and UD features per word, from LatinCy's spaCy models (`grc_dep_web_lg`, `la_core_web_lg`). This
is a second source of apo input beside OGA, in the same shape (see `scripts/PerseusTokens.roc`).

## Source

Each corpus is a public OCI artifact, `ghcr.io/perseusdlcode/mvp-tokens-<corpus>` (`greeklit`, `latinlit`,
`first1kgreek`, `grcnewxml`, `nd-dlc`), with one layer, `tokens.tar.zst` (`application/vnd.perseus.mvp.tokens`). It
holds one folder per edition (`greekLit/tlg0012/tlg001/perseus-grc2/`) with `index.json` (the chunks in citation
order), `metadata.json`, `tokens-manifest.json` (each chunk's language and pipeline), and one
`<chunk>.tokens.json.zst` per chunk. They are written by
[PerseusDLCode/tokenization_pipeline](https://github.com/PerseusDLCode/tokenization_pipeline)
(`src/mvp_tokenization/run_tokenizer.py`, sidecar schema 2).

Only chunks from schema 2 with a full spaCy analysis (pipeline `2:spacy-…:analyze`, Greek and Latin) convert; other
languages are tokenized only, and anything else fails the conversion. Perseus runs no parser today: HEAD and DEPREL are
empty, except that Latin's enclitic *-que* is attached to its host word (`cc`).

## Licenses

The pipeline code is MIT. The texts keep their own licenses, given in each edition's TEI header; most are CC BY-SA 4.0.
Perseus states no separate license for the annotation, so cite Perseus and keep the text's license for anything made
from a work.

## Pins

`pins.tsv` pins each corpus by its layer's digest: `corpus`, `image`, `digest`, `size`, and when Perseus built it. The
`latest` tag moves nightly, so nothing reads it except `kai run perseus-pin -- <corpus>`, which re-pins a corpus to
`latest`. After a bump, convert again and review the changes to what is committed (`conllu/perseus/`).

`kai run perseus-conllu -- <corpus> <work-urn> <out-dir> [<chunk-count>]` fetches the pinned archive into
`ARCHEION_PERSEUS_CACHE` (default `/var/tmp/archeion-perseus`) unless it is there, checks its SHA-256 against the pin,
and unpacks the work once. The registry keeps older digests (an earlier `latinlit` one still downloaded on 2026-11-05),
but nothing promises it will.

## Output

`<work>.conllu` and `<work>.refs.tsv`, as apo reads OGA's (`"token_ids": "misc-first"`,
`"passages": { "kind": "refs", … }`):

- Each token's first MISC item is its Perseus URN (`…:1.1@μῆνιν[1]`). Perseus gives punctuation none; its ID is built
  the same way from its identifier (`…:1.1@,[1]`). Then `SpaceAfter=No` and `TokenRange=start:end` (character offsets
  in the chunk's text).
- `<work>.refs.tsv` cites each token by its chunk, written as OGA's are (`1_33`). Chunks are Perseus's citable units:
  for the Iliad, cards of about 35 lines starting at the line they are named for, not single lines.
- Sentences never cross a chunk. With a parse (every word has a DEPREL), each tree is a sentence; without one, a
  sentence ends after `.` `;` `·` (Greek) or `.` `;` `?` `!` (Latin) and any punctuation attached to it. So a parse
  arriving can move sentence boundaries and `# sent_id`s (`<chunk urn>.<n>`), never token IDs or citations.
- Words are numbered from 1 in each sentence and heads made relative to it (root 0; `_` without a parse). Values are
  Perseus's, `null` as `_`; FORM is the source text. `apo validate` rejects `_` heads.
