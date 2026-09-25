#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Tests for scripts/review-lint.py: review JSON in, size report out; no network.
# shellcheck disable=SC2016

here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../../skills/openqa/scripts"
fixtures="$here/fixtures/review-lint"
src="$scripts/review-lint.py"
fail=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check() {
	if [ "$2" == "$3" ]; then
		echo "ok - $1"
	else
		echo "not ok - $1"
		printf '  expected: %q\n  actual:   %q\n' "$2" "$3"
		fail=1
	fi
}

# draft EVENT BODY [COMMENT...]: review JSON with a commit_id; comment N sits at tests/x.pm line N
draft() {
	python3 -c '
import json, sys
event, body, *comments = sys.argv[1:]
print(json.dumps({"commit_id": "0" * 40, "event": event, "body": body,
    "comments": [{"path": "tests/x.pm", "line": n, "body": text} for n, text in enumerate(comments, 1)]}))
' "$@"
}

lint() {
	python3 "$src" "$@" 2>&1
}

# result: "<exit code> <finding ids>" of the lint output in $out and $rc
result() {
	echo "$rc $(sed -n 's/^  F \([^ ]*\) .*/\1/p' <<<"$out" | paste -sd' ')" | sed 's/ $//'
}

text() {
	printf "%${1}s" "" | tr ' ' "${2:-x}"
}

# --- offline by construction -----------------------------------------------------
check "no network or process code" 0 "$(grep -Ec 'urllib|http\.client|socket|subprocess|os\.system|import _oqa' "$src")"
check "licence header" "# SPDX-License-Identifier: GPL-2.0-or-later" "$(sed -n 2p "$src")"
python3 "$src" --help >/dev/null
check "--help exits 0" 0 $?

# --- the review that prompted this ------------------------------------------------
out=$(lint "$fixtures/posted-26762.json" --lines 331 --late)
rc=$?
check "the posted 26762 review: no commit, over budget, one long body, late" "1 commit over-chars long-comment late" "$(result)"
out=$(lint "$fixtures/right-26762.json" --lines 331 --late)
rc=$?
check "its blocking-only rewrite passes even late" "0" "$(result)"
check "success names what is not checked" "size ok: 0/4 items, 0/1500 chars; the findings themselves are not checked" "$(tail -n 1 <<<"$out")"
out=$(draft COMMENT "" "fix it" "$(printf 'and this:\n```suggestion\nfixed\n```')" | lint --lines 12)
check "the item count survives a code block" "size ok: 2/3 items, 15/600 chars; the findings themselves are not checked" "$(tail -n 1 <<<"$out")"

# --- budget: count ------------------------------------------------------------------
# edge NAME COUNT LINES [ARGS]: COUNT items at the top of a size bucket, then one line later
edge() {
	local name=$1 count=$2 lines=$3
	shift 3
	local items=()
	for n in $(seq "$count"); do items+=("point $n"); done
	out=$(draft COMMENT "" "${items[@]}" | lint --lines "$lines" "$@")
	rc=$?
	check "$name: $count items on $lines lines is over" "1 over-count" "$(result)"
	out=$(draft COMMENT "" "${items[@]}" | lint --lines "$((lines + 1))" "$@")
	rc=$?
	check "$name: $count items on $((lines + 1)) lines is not" "0" "$(result)"
}
edge "tests <=20" 4 20
out=$(draft COMMENT "" 1 2 3 4 5 | lint --lines 100)
rc=$?
check "tests 21-100: 5 items on 100 lines" "0" "$(result)"
out=$(draft COMMENT "" 1 2 3 4 5 6 | lint --lines 100)
rc=$?
check "tests 21-100: 6 items on 100 lines is over" "1 over-count" "$(result)"
edge "lib <=20" 3 20 --lib
edge "lib 21-100" 5 100 --lib
edge "lib 101-300" 6 300 --lib
out=$(draft COMMENT "" 1 2 3 4 | lint --lines 300)
rc=$?
check "tests 101-300: 4 items" "0" "$(result)"
out=$(draft COMMENT "" 1 2 3 4 5 | lint --lines 101)
rc=$?
check "tests over 100 lines: 5 items" "1 over-count" "$(result)"
out=$(draft COMMENT "" 1 2 3 4 5 6 7 8 9 | lint --lines 400 --lib)
rc=$?
check "lib over 300 lines: 9 items" "1 over-count" "$(result)"
out=$(draft COMMENT "" 1 2 3 4 5 6 7 8 | lint --lines 400 --lib)
rc=$?
check "lib over 300 lines: 8 items" "0" "$(result)"
out=$(draft COMMENT "" "a" "b" "c" | lint --lines 5 --replies 1)
rc=$?
check "a thread reply counts as an item" "1 over-count" "$(result)"
check "  and is shown" 1 "$(grep -c '; replies 1$' <<<"$out")"
lint --lines 5 --replies -1 <<<'{"event": "APPROVE"}' >/dev/null
check "negative --replies exits 2" 2 $?
out=$(draft COMMENT "x" "a" "b" "c" | lint --lines 5)
rc=$?
check "a body counts as an item" "1 over-count" "$(result)"
long="blocking: $(text 900)"
out=$(draft COMMENT "" "$long 1" "$long 2" "$long 3" "$long 4" "$long 5" | lint --lines 10)
rc=$?
check "blocking comments count against no budget" "0" "$(result)"
out=$(draft COMMENT "" "Blocking: $(text 900)" | lint --lines 10)
rc=$?
check "the prefix is case-insensitive" "0" "$(result)"

# --- budget: characters ----------------------------------------------------------
out=$(draft COMMENT "" "$(text 300)" "$(text 300 y)" | lint --lines 20)
rc=$?
check "600 chars on 20 lines" "0" "$(result)"
out=$(draft COMMENT "" "$(text 300)" "$(text 301 y)" | lint --lines 20)
rc=$?
check "601 chars on 20 lines" "1 over-chars" "$(result)"
out=$(draft COMMENT "" "$(text 500)" "$(text 501 y)" | lint --lines 100)
rc=$?
check "1001 chars on 100 lines" "1 over-chars" "$(result)"
out=$(draft COMMENT "" "$(text 500)" "$(text 501 y)" | lint --lines 101)
rc=$?
check "1001 chars on 101 lines" "0" "$(result)"
out=$(draft COMMENT "" "$(text 500)" "$(text 500 y)" "$(text 500 z)" | lint --lines 300)
rc=$?
check "1500 chars on 300 lines" "0" "$(result)"
out=$(draft COMMENT "" "$(text 500)" "$(text 500 y)" "$(text 501 z)" | lint --lines 300)
rc=$?
check "1501 chars on 300 lines" "1 over-chars" "$(result)"
out=$(draft COMMENT "" "$(text 500)" "$(text 500 y)" "$(text 501 z)" | lint --lines 400)
rc=$?
check "1501 chars on 400 lines" "1 over-chars" "$(result)"
out=$(draft COMMENT "" "see https://example.org/$(text 900)" | lint --lines 10)
rc=$?
check "URLs are not prose" "0" "$(result)"
out=$(draft COMMENT "" "$(printf 'Change it:\n```suggestion\n%s\n```' "$(text 900)")" | lint --lines 10)
rc=$?
check "suggestion blocks are not prose" "0" "$(result)"
accents=$(python3 -c 'print("e\u0301" * 400)')
out=$(draft COMMENT "" "$accents" | lint --lines 400)
rc=$?
check "decomposed accents count once" "0" "$(result)"
out=$(draft COMMENT "" "$(text 600)$(python3 -c 'print("\u200b" * 100, end="")')" | lint --lines 400)
rc=$?
check "zero-width characters do not count" "0" "$(result)"

# --- one item ---------------------------------------------------------------------
out=$(draft COMMENT "" "$(text 600)" | lint --lines 200)
rc=$?
check "a 600-char comment" "0" "$(result)"
out=$(draft COMMENT "" "$(text 601)" | lint --lines 200)
rc=$?
check "a 601-char comment is long" "1 long-comment" "$(result)"
out=$(draft COMMENT "$(text 601)" | lint --lines 200)
rc=$?
check "a 601-char body alone is long" "1 long-comment" "$(result)"
out=$(draft COMMENT "" "blocking: $(text 990)" | lint --lines 10)
rc=$?
check "a 1000-char blocking comment" "0" "$(result)"
out=$(draft COMMENT "" "blocking: $(text 991)" | lint --lines 10)
rc=$?
check "a 1001-char blocking comment is long" "1 long-comment" "$(result)"
out=$(draft COMMENT "$(text 300)" "fix it" | lint --lines 200)
rc=$?
check "a 300-char body beside comments" "0" "$(result)"
out=$(draft COMMENT "$(text 301)" "fix it" | lint --lines 200)
rc=$?
check "a 301-char body beside comments is long" "1 long-body" "$(result)"
out=$(draft COMMENT "" "$(printf '```foo``` is wrong\n%s' "$(text 700)")" | lint --lines 200)
rc=$?
check "a line-leading code span is not a fence" "1 long-comment" "$(result)"
out=$(draft COMMENT "" "$(printf '\t```\n%s' "$(text 700)")" | lint --lines 200)
rc=$?
check "a tab-indented fence is not a fence" "1 long-comment" "$(result)"

# --- nits ---------------------------------------------------------------------------
out=$(draft COMMENT "" "fix it" "nit: a" "nit: b" | lint --lines 50)
rc=$?
check "2 nits" "0" "$(result)"
out=$(draft COMMENT "" "fix it" "nit: a" "nit: b" "nit: c" | lint --lines 400 --lib)
rc=$?
check "3 nits are too many" "1 nits" "$(result)"
out=$(draft COMMENT "nit: a" "fix it" "nit: b" "nit: c" | lint --lines 400 --lib)
rc=$?
check "a nit in the body counts" "1 nits" "$(result)"
out=$(draft COMMENT "" "fix it" "nit: $(text 145)" | lint --lines 50)
rc=$?
check "a 150-char nit, prefix included" "0" "$(result)"
out=$(draft COMMENT "" "fix it" "nit: $(text 146)" | lint --lines 50)
rc=$?
check "a 151-char nit is long" "1 long-nit" "$(result)"
out=$(draft COMMENT "" "fix it" "$(printf 'nit: a\nand b')" | lint --lines 50)
rc=$?
check "a two-line nit is long" "1 long-nit" "$(result)"
out=$(draft COMMENT "" "fix it" "$(printf 'nit: a\rand b')" | lint --lines 50)
rc=$?
check "a lone CR ends a line" "1 long-nit" "$(result)"
out=$(draft COMMENT "" "fix it" "$(printf 'nit: typo\n```suggestion\nfixed\n```')" | lint --lines 50)
rc=$?
check "a nit with a suggestion block is one line" "0" "$(result)"
out=$(draft COMMENT "" "nit: a" | lint --lines 50)
rc=$?
check "nits alone" "1 lone-nits" "$(result)"
out=$(draft COMMENT "nit: a" | lint --lines 50)
rc=$?
check "a nit alone in the body" "1 lone-nits" "$(result)"
out=$(draft COMMENT "Looks good overall." "nit: a" | lint --lines 50)
rc=$?
check "a body is not a change request for nits" "1 lone-nits" "$(result)"
out=$(draft COMMENT "" "blocking: broken" "nit: a" | lint --lines 50)
rc=$?
check "a nit beside a blocking finding" "0" "$(result)"

# --- prefixes -------------------------------------------------------------------------
out=$(draft COMMENT "" "**nit:** a" | lint --lines 50)
rc=$?
check "an emphasised nit prefix" "1 prefix" "$(result)"
out=$(draft COMMENT "" "Nitpick: a" | lint --lines 50)
rc=$?
check "a nitpick prefix" "1 prefix" "$(result)"
out=$(draft COMMENT "" "**blocking:** broken" | lint --lines 50 --late)
rc=$?
check "an emphasised blocking prefix is not blocking" "1 prefix late" "$(result)"
out=$(draft COMMENT "" "$(printf '\n  blocking: broken')" | lint --lines 50 --late)
rc=$?
check "leading whitespace before the prefix" "0" "$(result)"
out=$(draft COMMENT "" "Nitrogen is missing" "Blocking the port here hangs the job" | lint --lines 50)
rc=$?
check "prose opening with Nitrogen or Blocking is not a prefix" "0" "$(result)"
out=$(draft COMMENT "" "$(printf '\u200bblocking: broken')" | lint --lines 50 --late)
rc=$?
check "a zero-width space before the prefix" "0" "$(result)"
out=$(draft COMMENT "" "$(printf '> x\n\nblocking: y')" | lint --lines 50 --late)
rc=$?
check "the prefix after a quote" "1 prefix late" "$(result)"

# --- form -----------------------------------------------------------------------------
out=$(draft COMMENT "" "same   point" "Same point" | lint --lines 50)
rc=$?
check "the same text twice" "1 duplicate" "$(result)"
sugg=$(printf '```suggestion\nuse strict;\n```')
out=$(draft COMMENT "" "$sugg" "$sugg" | lint --lines 50)
rc=$?
check "the same suggestion on two lines" "0" "$(result)"
# block MARKER N: a comment with an N-line fenced block
block() {
	printf 'see:\n%s\n%s\n%s\nafter' "$1" "$(for _ in $(seq "$2"); do echo "log line"; done)" "${1%%[a-z]*}"
}
out=$(draft COMMENT "" "$(block '```' 10)" | lint --lines 50)
rc=$?
check "a 10-line code block" "0" "$(result)"
out=$(draft COMMENT "" "$(block '```' 11)" | lint --lines 50)
rc=$?
check "an 11-line code block is pasted" "1 pasted-block" "$(result)"
out=$(draft COMMENT "" "$(block '~~~' 11)" | lint --lines 50)
rc=$?
check "an 11-line tilde block is pasted" "1 pasted-block" "$(result)"
out=$(draft COMMENT "" "$(printf 'see:\n```\n%s\n```' "$(text 800)")" | lint --lines 50)
rc=$?
check "an 800-char code line" "0" "$(result)"
out=$(draft COMMENT "" "$(block '   ```' 11)" | lint --lines 50)
rc=$?
check "an indented 11-line block is pasted" "1 pasted-block" "$(result)"
out=$(draft COMMENT "" "$(printf 'see:\n```\n%s\n```' "$(text 801)")" | lint --lines 50)
rc=$?
check "an 801-char code line is pasted" "1 pasted-block" "$(result)"
out=$(draft COMMENT "" "$(block '```suggestion' 12)" | lint --lines 50)
rc=$?
check "a 12-line suggestion block is not pasted" "0" "$(result)"
out=$(draft COMMENT "" "$(printf 'see:\n```\ncode')" | lint --lines 50)
rc=$?
check "an unclosed fence" "1 unclosed-fence" "$(result)"
out=$(draft COMMENT "" "$(printf '> a\n> b\nno')" | lint --lines 50)
rc=$?
check "two quoted lines" "0" "$(result)"
out=$(draft COMMENT "" "$(printf '> a\n>\n> b\nwhy')" | lint --lines 50)
rc=$?
check "a bare > line is not quoted text" "0" "$(result)"
out=$(draft COMMENT "" "$(printf '> a\n> b\n> c\nno')" | lint --lines 50)
rc=$?
check "three quoted lines" "1 quotes" "$(result)"
out=$(draft COMMENT "" "$(printf '> %s\nno' "$(text 300)")" | lint --lines 50)
rc=$?
check "a 300-char quote" "0" "$(result)"
out=$(draft COMMENT "" "$(printf '> %s\nno' "$(text 301)")" | lint --lines 50)
rc=$?
check "a 301-char quote" "1 quotes" "$(result)"
out=$(draft COMMENT "" "fix it" | lint --lines 50 --late)
rc=$?
check "late: a non-blocking comment" "1 late" "$(result)"
out=$(draft APPROVE "" "fix it" | lint --lines 50)
rc=$?
check "an approval with a comment" "1 event" "$(result)"
out=$(draft REQUEST_CHANGES "" "fix it" | lint --lines 50)
rc=$?
check "request changes without a blocking comment" "1 event" "$(result)"
out=$(draft COMMENT "" | lint --lines 50)
rc=$?
check "an empty comment review" "1 event" "$(result)"
check "  suggests approving or nothing" 1 "$(grep -c 'approve if the user wants to, or post nothing' <<<"$out")"
out=$(draft COMMENT "" | lint --lines 50 --late)
rc=$?
check "an empty late review" "1 event" "$(result)"
check "  says to post nothing" 1 "$(grep -c 'nothing blocking, so post nothing' <<<"$out")"
out=$(draft APPROVE "" | lint --lines 50)
rc=$?
check "an empty approval" "0" "$(result)"
out=$(lint --lines 50 <<<'{"event": "APPROVE"}')
rc=$?
check "no commit_id" "1 commit" "$(result)"
out=$(lint --lines 50 <<<'{"commit_id": "abc", "event": "APPROVE", "body": null}')
rc=$?
check "a null body is empty" "0" "$(result)"

# --- hostile or broken input ------------------------------------------------------------
out=$(python3 -c '
import json
print(json.dumps({"commit_id": "0", "event": "COMMENT", "comments": [
    {"path": "a\u001b[31m\nINJECTED=1", "line": 1, "body": "x"},
    {"path": "\u200b" * 460 + "ghp_" + "B" * 36, "line": 2, "body": "x"}]}))' | lint --lines 5)
rc=$?
check "a hostile path stays on one clean line" "1 duplicate" "$(result)"
check "no escape, injected line or token reaches the output" "0 0 0" \
	"$(grep -c $'\e' <<<"$out") $(grep -c '^INJECTED' <<<"$out") $(grep -c 'ghp_B' <<<"$out")"
many=()
for _ in {1..45}; do many+=(x); done
out=$(draft COMMENT "" "${many[@]}" | lint --lines 5)
check "more than 40 findings are cut" "40 ... 5 more not shown" "$(grep -c '^  F ' <<<"$out") $(tail -n 1 <<<"$out" | sed 's/^ *//')"
for bad in 'not json' '[]' '{"body": "x"}' '{"event": "COMMENT", "body": 5}' '{"event": "COMMENT", "commit_id": 5}' \
	'{"event": "COMMENT", "comments": {}}' '{"event": "COMMENT", "comments": [{"path": "a", "line": 1}]}' \
	'{"event": "COMMENT", "comments": [{"path": "a", "line": 1, "body": "  "}]}' \
	'{"event": "COMMENT", "comments": [{"line": 1, "body": "x"}]}' \
	'{"event": "COMMENT", "comments": [{"path": "a", "body": "x"}]}' \
	'{"event": "COMMENT", "comments": [{"path": "a", "line": true, "body": "x"}]}'; do
	lint --lines 5 <<<"$bad" >/dev/null
	check "not a review exits 2: $bad" 2 $?
done
python3 -c 'print("[" * 100000)' | lint --lines 5 >"$work/out"
check "deep nesting exits 2 without a traceback" "2 0" "$? $(grep -c Traceback "$work/out")"
lint --lines -1 <<<'{"event": "APPROVE"}' >/dev/null
check "negative --lines exits 2" 2 $?
python3 -c 'print("{\"event\": \"APPROVE\"}" + " " * 270000)' | lint --lines 5 >/dev/null
check "an oversized draft on stdin exits 2" 2 $?
python3 -c 'print("{\"event\": \"APPROVE\"}" + " " * 270000)' >"$work/big.json"
check "an oversized FILE exits 2" "error: draft longer than 262144 characters" "$(lint "$work/big.json" --lines 5)"
# Reads stop at the cap: under a memory limit an uncapped read of 400 MB fails with MemoryError.
truncate -s 400M "$work/sparse.json"
out=$(ulimit -v 500000 && lint "$work/sparse.json" --lines 5)
check "a 400 MB FILE is read only up to the cap" "error: draft longer than 262144 characters" "$out"
out=$(ulimit -v 500000 && head -c 400M /dev/zero | lint --lines 5)
check "400 MB on stdin are read only up to the cap" "error: draft longer than 262144 characters" "$out"
printf '{"commit_id": "0", "event": "COMMENT", "body": "caf\xe9 \xff"}' >"$work/bytes.json"
out=$(lint "$work/bytes.json" --lines 5)
rc=$?
check "bytes that are not UTF-8 are read" "0 0" "$rc $(grep -c Traceback <<<"$out")"
check "'-' reads stdin like FILE" "$out" "$(lint - --lines 5 <"$work/bytes.json")"
lint "$fixtures" --lines 5 >/dev/null
check "a directory exits 2" 2 $?
mkfifo "$work/fifo"
check "a FIFO is refused instead of blocking" 'error: "fifo": not a regular file' "$(cd "$work" && timeout 10 python3 "$src" fifo --lines 5 2>&1)"
ln -s /dev/zero "$work/zero.json"
check "a device is refused" 'error: "zero.json": not a regular file' "$(cd "$work" && lint zero.json --lines 5)"
lint "$work/missing.json" --lines 5 >/dev/null
check "a missing file exits 2" 2 $?
out=$(lint "$work/"$'no\nsuch\e[31m.json' --lines 5)
check "a hostile file name stays on one line without escapes" "1 0" "$(wc -l <<<"$out") $(grep -c $'\e' <<<"$out")"

exit $fail
