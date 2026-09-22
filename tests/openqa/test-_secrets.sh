#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Tests for scripts/_secrets.py: credential-shaped values are replaced, and normal log
# content is not. The negative cases matter more than the positive ones - a redactor
# that eats evidence gets switched off, and then it protects nothing.

here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../../skills/openqa/scripts"
fixtures="$here/fixtures/_secrets"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

check() {
	if [ "$2" == "$3" ]; then
		echo "ok - $1"
	else
		echo "not ok - $1"
		printf '  expected: %q\n  actual:   %q\n' "$2" "$3"
		fail=1
	fi
}

# redacts <name> <printf-format> <rule expected in the summary>
redacts() {
	local out
	# shellcheck disable=SC2059
	out=$(printf -- "$2" | python3 "$scripts/_secrets.py" 2>&1)
	case "$out" in
	*"[REDACTED:$3]"*) echo "ok - $1" ;;
	*)
		echo "not ok - $1"
		printf '  wanted rule %q in: %q\n' "$3" "$out"
		fail=1
		;;
	esac
}

# keeps <name> <printf-format>: nothing may be redacted
keeps() {
	local out
	# shellcheck disable=SC2059
	out=$(printf -- "$2" | python3 "$scripts/_secrets.py" 2>/dev/null)
	case "$out" in
	*"[REDACTED:"*)
		echo "not ok - $1"
		printf '  false positive: %q\n' "$out"
		fail=1
		;;
	*) echo "ok - $1" ;;
	esac
}

# --- read-only by construction ---------------------------------------------------
src="$scripts/_secrets.py"
check "source names no network, process or environment access" 0 \
	"$(grep -Ec 'urllib|http\.client|import socket|urlopen|subprocess|os\.system|os\.environ|getenv|expanduser|netrc' "$src")"
check "licence header" "# SPDX-License-Identifier: GPL-2.0-or-later" "$(sed -n 2p "$src")"

# --- credentials that must not reach the agent -----------------------------------
redacts "github token" 'fatal: token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA rejected\n' github-token
redacts "gitlab token" 'glpat-AAAAAAAAAAAAAAAAAAAA\n' gitlab-token
redacts "aws access key id" 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE\n' aws-key-id
redacts "slack token" 'xoxb-1234567890-abcdefghij\n' slack-token
redacts "jwt" 'Cookie: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP\n' jwt
redacts "url userinfo" 'zypper ar https://alice:hunter2@example.org/repo x\n' url-userinfo
redacts "authorization header" '> Authorization: Bearer abcdefghijklmnop\n' auth-header
redacts "curl -u" '+ curl -u alice:s3cretvalue https://example.org/api\n' curl-user
redacts "password flag of a known command" '+ helm registry login ex.io -u bob -p Sup3rS3cret\n' password-flag
redacts "registry auth blob" '{"auths":{"x":{"auth":"dXNlcjpwYXNzd29yZA=="}}}\n' registry-auth
redacts "keyed assignment" 'SCC_REGCODE=ABCD1234EFGH5678\n' keyed-assignment
redacts "private key block" '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaA\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n' private-key

# The body of a key is base64 that no line rule would match; it must not survive.
actual=$(printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----\n' |
	python3 "$scripts/_secrets.py" 2>/dev/null)
check "the key body is swallowed, not printed line by line" 0 "$(grep -c MIIEowIBAAKCAQEA <<<"$actual")"

# A BEGIN with no END means the body is still ahead: fail closed.
actual=$(printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n' | python3 "$scripts/_secrets.py" 2>/dev/null)
check "an unterminated key block fails closed" 0 "$(grep -c MIIEowIBAAKCAQEA <<<"$actual")"

# --- what must survive, or the redactor destroys the evidence it exists to show ---
keeps "JOBTOKEN, dead once the job finishes" '"JOBTOKEN" : "FkZT9GDzQrravzhD",\n'
keeps "the conventional openQA password" 'EXTRABOOTPARAMS=... live.password=nots3cr3t\n'
keeps "a sha256 digest" 'checksum e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n'
keeps "a uuid on the kernel command line" 'root=UUID=123e4567-e89b-12d3-a456-426614174000 ro\n'
# shellcheck disable=SC2016
keeps "a shell template" 'ARM_CLIENT_SECRET=${AZURE_SECRET}\n'
keeps "an empty-ish value" 'TOKEN=none\n'
keeps "a socket path" 'SSH_AUTH_SOCK=/tmp/ssh-XXXX/agent.1234\n'
keeps "needle candidates" 'candidates: bootloader-20260919:96%% inst-welcome:88%%\n'
keeps "an ordinary log line" '[debug] loading console/opencode on openqaworker20\n'
keeps "a git hash" 'TEST_GIT_HASH=3f718db6c0de4a2b1e5f8a9c7d6e5f4a3b2c1d0e\n'
keeps "a public repo url with no userinfo" 'zypper ar https://download.opensuse.org/tumbleweed/repo/oss/ oss\n'

# The negative fixture is the control for over-redaction: it must stay byte-identical.
actual=$(python3 "$scripts/_secrets.py" <"$fixtures/clean-log.txt" 2>/dev/null)
check "a whole realistic log survives untouched" "$(cat "$fixtures/clean-log.txt")" "$actual"
check "and reports nothing" "" "$(python3 "$scripts/_secrets.py" --quiet <"$fixtures/clean-log.txt" 2>&1 >/dev/null)"

# --- the summary, so a redaction is never silent ----------------------------------
actual=$(printf 'curl -u a:secretvalue https://x/ and ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' |
	python3 "$scripts/_secrets.py" 2>&1 >/dev/null)
check "stderr names every rule that fired" "redacted 2: curl-user=1, github-token=1" "$actual"
printf 'curl -u a:secretvalue https://x/\n' | python3 "$scripts/_secrets.py" >/dev/null 2>&1
check "exit code 1 when something was redacted" 1 $?
printf 'nothing to see\n' | python3 "$scripts/_secrets.py" >/dev/null 2>&1
check "exit code 0 when nothing was" 0 $?
check "--quiet prints no summary" "" \
	"$(printf 'curl -u a:secretvalue https://x/\n' | python3 "$scripts/_secrets.py" --quiet 2>&1 >/dev/null)"

# --- settings are keyed by name, which no value-shape rule can know ---------------
actual=$(python3 -c "
import sys; sys.path.insert(0, '$scripts')
import _secrets
for key in ('SCC_REGCODE', '_SECRET_DOCKER', 'ROOT_PASSWORD', 'JOBTOKEN', 'CASEDIR', 'BUILD'):
    print(key, _secrets.is_secret_key(key))
")
check "openQA's own names, plus the regcodes it misses, minus the dead token" "$(
	cat <<'EOF'
SCC_REGCODE True
_SECRET_DOCKER True
ROOT_PASSWORD True
JOBTOKEN False
CASEDIR False
BUILD False
EOF
)" "$actual"

# --- structure and cost -----------------------------------------------------------
actual=$(printf 'a\nb\nc\n' | python3 "$scripts/_secrets.py" 2>/dev/null | wc -l)
check "line structure is preserved" 3 "$actual"
SECONDS=0
python3 -c "
import sys; sys.path.insert(0, '$scripts')
import _secrets
_secrets.redact('worker openqaworker20 ran module foo at 12:00:00\n' * 20000)
"
check "20k ordinary lines stay well under a second of budget" 1 "$((SECONDS < 10))"

# --- site formats, which a public repository cannot carry ---------------------------
printf '# a site format\nSUSE-[A-Z0-9]{8}-[A-Z0-9]{4}\n' >"$work/patterns.txt"
actual=$(printf 'regcode SUSE-ABCD1234-EF56 accepted\n' |
	python3 "$scripts/_secrets.py" --scrub-patterns "$work/patterns.txt" 2>/dev/null)
check "a site pattern is applied" "regcode [REDACTED:site] accepted" "$actual"
printf 'x(\n' >"$work/bad.txt"
python3 "$scripts/_secrets.py" --scrub-patterns "$work/bad.txt" </dev/null >/dev/null 2>&1
check "a bad site regex is a usage error, not a traceback" 2 $?
python3 "$scripts/_secrets.py" --scrub-patterns "$work/missing.txt" </dev/null >/dev/null 2>&1
check "a missing patterns file is a usage error" 2 $?

python3 "$scripts/_secrets.py" --help >/dev/null
check "--help exits 0" 0 $?
python3 "$scripts/_secrets.py" --bogus </dev/null >/dev/null 2>&1
check "bad option exits 2" 2 $?

exit $fail
