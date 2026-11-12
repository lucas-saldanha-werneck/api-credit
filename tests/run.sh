#!/bin/bash
# Tests for claude-credito and install.sh. Everything runs in a temporary folder with a fake HOME and a
# fake `claude` (a shell script that answers by the key it was given). No real claude, no API, no Keychain.
# Run: bash tests/run.sh
T="$(cd "$(dirname "$0")" && pwd)"
R="$(dirname "$T")"
W="$(mktemp -d "${TMPDIR:-/tmp}/claude-credito-test.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS: $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }
check() { # name, got, want
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi
}

# Settings from the developer's shell must not reach the tests.
for v in $(env | sed -n 's/^\(CLAUDE_CREDITO[A-Z_]*\)=.*/\1/p'); do unset "$v"; done
unset ANTHROPIC_API_KEY XDG_CONFIG_HOME XDG_STATE_HOME
export HOME="$W/home" FAKE_DIR="$W" CLAUDE_CREDITO_KEYCHAIN=off
mkdir -p "$HOME" "$W/fakebin" "$W/work"
export PATH="$W/fakebin:/usr/bin:/bin"
CC="$R/bin/claude-credito"
PRE="sk-ant-"; GOOD="${PRE}test-good"; LOW="${PRE}test-low"; MIDLOW="${PRE}test-midlow"; WRONG="${PRE}test-wrong"; TOOLTEXT="${PRE}test-tooltext"   # not real keys
LOG="$HOME/.local/state/claude-credito/claude-credito.log"
STATE_DIR="$HOME/.local/state/claude-credito"
PAUSE="$STATE_DIR/paused-*"   # one pause file per key (a glob: test with paused_any)
paused_any() { ls $PAUSE >/dev/null 2>&1; }

cat > "$W/fakebin/claude" <<'EOF'
#!/bin/bash
# fake claude: records each call and answers by the key it was given. Like the real one (checked with
# claude 2.1.322), with --session-id it writes a transcript, where an API error is a "<synthetic>"
# assistant line with "isApiErrorMessage":true and a real turn is an assistant line with a real model;
# with --output-format json/stream-json the result line has is_error and modelUsage ({} = no API call worked).
# Like the real claude, FAKE_STDIN_GIVEUP gives up on a stdin that stays silent (here after 1 s).
# Like the real claude (2.1.319 and 2.1.322 on macOS), a NAMED FIFO as stdin is read but its end is never
# seen, so it hangs; an anonymous pipe is fine. Here: read it, wait 5 s, fail.
named_fifo() {
  [ -p /dev/stdin ] || return 1
  if [ -e "/proc/$$/fd/0" ]; then case "$(readlink "/proc/$$/fd/0")" in /*) return 0 ;; esac; return 1; fi
  PATH="$PATH:/usr/sbin:/sbin" lsof -a -p $$ -d 0 -Fn 2>/dev/null | grep -q '^n/'
}
if named_fifo; then cat > /dev/null; sleep 5; echo "fake claude: stuck on a named FIFO stdin" >&2; exit 99; fi
if [ -n "${FAKE_STDIN_GIVEUP:-}" ]; then in=""; IFS= read -r -t 1 in || true; else in="$(cat)"; fi
[ -n "${FAKE_SLEEP:-}" ] && { echo $$ > "$FAKE_DIR/pid"; exec sleep "$FAKE_SLEEP"; }
echo "key=${ANTHROPIC_API_KEY:-none} stdin=[$in] args=$*" >> "$FAKE_DIR/calls"
sid=""; fmt=text; prev=""
for a in "$@"; do
  case "$prev" in --session-id) sid="$a" ;; --output-format) fmt="$a" ;; esac
  case "$a" in --output-format=*) fmt="${a#*=}" ;; esac
  prev="$a"
done
transcript() {
  [ -n "$sid" ] && [ -z "${FAKE_NO_TRANSCRIPT:-}" ] || return 0
  d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/-fake-work"; mkdir -p "$d"
  printf '%s\n' "$@" >> "$d/$sid.jsonl"
}
USER='{"type":"user","message":{"role":"user","content":"q"}}'
REAL='{"type":"assistant","message":{"model":"claude-x","role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}'
syn() { printf '{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"%s"}]},"error":"authentication_failed","isApiErrorMessage":true}' "$1"; }
# answer TEXT RC ACTED(0/1) API_ERROR(0/1)
answer() {
  usage='{}'; [ "$3" = 1 ] && usage='{"claude-x":{"inputTokens":9}}'
  err=false; [ "$4" = 1 ] && err=true
  if [ "$3" = 1 ]; then transcript "$USER" "$REAL"; else transcript "$USER"; fi
  [ "$4" = 1 ] && transcript "$(syn "$1")"
  res='{"type":"result","subtype":"success","is_error":'$err',"num_turns":1,"modelUsage":'$usage',"result":"'$1'"}'
  case "$fmt" in
    json) echo "$res" ;;
    stream-json) echo '{"type":"system","subtype":"init"}'; head -c 7000 /dev/zero | tr '\0' x; echo; echo "$res" ;;
    *) echo "$1" ;;
  esac
  exit "$2"
}
case "${ANTHROPIC_API_KEY:-}" in
  "")       echo "sub-ok [$in]"; echo "sub-err" >&2; exit "${FAKE_SUB_RC:-0}" ;;
  *good)    if [ -n "${FAKE_RAW:-}" ]; then printf '\xe2\x9a\xa0 claude.ai connectors are disabled because %s is set\nraw\0bytes, no final newline' "ANTHROPIC_API_KEY"; exit 0; fi
            if [ -n "${FAKE_MENTION:-}" ]; then answer "The log shows Invalid API key in service X" "${FAKE_API_RC:-0}" 1 0; fi
            transcript "$USER" "$REAL"
            echo "⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY is set"
            if [ -n "${FAKE_BIG:-}" ]; then head -c 7000 /dev/zero | tr '\0' x; echo " Invalid API key"; fi
            echo "api-ok [$in]"; echo "api-err" >&2; exit "${FAKE_API_RC:-0}" ;;
  *midlow)  answer "Credit balance is too low" 1 1 1 ;;   # it acted (a tool ran), then the credit ran out
  *tooltext) # a real turn whose tool input holds the text "model":"<synthetic>", then the credit ran out
            transcript "$USER" '{"type":"assistant","message":{"model":"claude-x","role":"assistant","content":[{"type":"tool_use","name":"Agent","input":{"model":"<synthetic>"}}]}}' "$(syn "Credit balance is too low")"
            echo "Credit balance is too low"; exit 1 ;;
  *low)     answer "Credit balance is too low" 1 0 1 ;;   # refused on the first request
  *)        answer "Invalid API key · Fix external API key" 0 0 1 ;;   # some versions exit 0 here
esac
EOF
chmod +x "$W/fakebin/claude"
calls() { if [ -f "$W/calls" ]; then wc -l < "$W/calls" | tr -d ' '; else echo 0; fi; }
reset() { rm -f "$W/calls" $PAUSE "$LOG"; }
cd "$W/work" || exit 1

echo "== which call uses the API"
reset
OUT=$(CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" "hello" </dev/null 2>/dev/null)
check "no -p: plain claude, no key" "$OUT|$(cat "$W/calls")" "sub-ok []|key=none stdin=[] args=hello"
reset
OUT=$(echo "question" | CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p --model x 2>"$W/err")
check "-p with a key: API answer, notice line removed" "$OUT" "api-ok [question]"
check "-p with a key: stderr kept" "$(cat "$W/err")" "api-err"
check "-p with a key: one call, with the key and the same arguments" "$(sed -E 's/--session-id [0-9a-f-]{36} //' "$W/calls")" "key=$GOOD stdin=[question] args=-p --model x"
grep -q " api rc=0 (" "$LOG" && ok "log line: api rc=0" || bad "log: $(cat "$LOG" 2>&1)"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" --print 2>/dev/null); check "--print counts as -p" "$OUT" "api-ok [q]"
reset
OUT=$(echo q | CLAUDE_CREDITO=off CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p 2>/dev/null); check "CLAUDE_CREDITO=off: subscription" "$OUT" "sub-ok [q]"
reset
OUT=$(echo q | ANTHROPIC_API_KEY="${PRE}callers-own-good" CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p 2>/dev/null)
check "caller's own ANTHROPIC_API_KEY is left alone" "$OUT|$(calls)" "⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY is set
api-ok [q]|1"
reset
OUT=$(echo q | bash "$CC" -p 2>/dev/null); check "no key stored: subscription" "$OUT|$(calls)" "sub-ok [q]|1"
grep -q "subscription (no key stored" "$LOG" && ok "log says no key" || bad "log: $(cat "$LOG" 2>&1)"
reset
echo q | CLAUDE_CREDITO_KEY="$GOOD" FAKE_API_RC=3 bash "$CC" -p >/dev/null 2>&1; check "exit code of the API call is kept" "$?" "3"

echo "== the API refuses"
reset
OUT=$(echo "question" | CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p 2>"$W/err")
check "credit too low: the subscription answers" "$OUT" "sub-ok [question]"
check "credit too low: two calls, same stdin" "$(cut -d' ' -f1,2 "$W/calls" | tr '\n' ';')" "key=$LOW stdin=[question];key=none stdin=[question];"
paused_any && ok "pause file written" || bad "no pause file"
grep -q "API REFUSED (Credit balance is too low, rc=1)" "$LOG" && grep -q "subscription rc=0" "$LOG" && ok "log lines: refused, subscription" || bad "log: $(cat "$LOG")"
OUT=$(echo q | CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p 2>/dev/null)
check "paused: that key goes straight to the subscription" "$OUT|$(calls)" "sub-ok [q]|3"
OUT=$(echo q | CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p 2>/dev/null)
check "AC-08: another key is not paused by that refusal" "$OUT|$(calls)" "api-ok [q]|4"
OUT=$(CLAUDE_CREDITO_KEY="$LOW" bash "$CC" --credit-status); echo "$OUT" | grep -q "^pause: on since" && ok "status shows the pause of the key in use" || bad "$OUT"
ls "$STATE_DIR"/paused-* 2>/dev/null | grep -q "test-low" && bad "the key itself is in the pause file name" || ok "pause file name holds no key text"
OUT=$(echo q | CLAUDE_CREDITO_PAUSE_S=0 CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p 2>/dev/null)
check "pause over: API again (refused again here, so paused again)" "$OUT|$(calls)" "sub-ok [q]|6"
: > "$STATE_DIR/paused-x"; OUT=$(bash "$CC" --credit-resume); paused_any || check "--credit-resume ends every pause" "$OUT" "pause ended"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$WRONG" bash "$CC" -p 2>/dev/null)
check "invalid key answered with exit 0: still seen as a refusal" "$OUT|$(calls)" "sub-ok [q]|2"
reset
echo q | CLAUDE_CREDITO_KEY="$LOW" FAKE_SUB_RC=4 bash "$CC" -p >/dev/null 2>&1; check "after a refusal the subscription's exit code is returned" "$?" "4"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$GOOD" FAKE_BIG=1 bash "$CC" -p 2>/dev/null | tail -n 1)
check "a long answer that mentions 'Invalid API key' is not a refusal" "$OUT|$(calls)" "api-ok [q]|1"

echo "== repeat only when no turn ran"
reset
echo q | CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p x >/dev/null 2>&1
grep -qE "^key=$LOW stdin=\[q\] args=--session-id [0-9a-f-]{36} -p x$" "$W/calls" && grep -q "^key=none stdin=\[q\] args=-p x$" "$W/calls" \
  && ok "text call: own --session-id on the API call; the repeat gets the caller's arguments only" || bad "$(cat "$W/calls")"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$MIDLOW" bash "$CC" -p 2>/dev/null); rc=$?
check "credit ran out after a tool ran: not repeated, the error and exit code are returned" "$OUT|$rc|$(calls)" "Credit balance is too low|1|1"
paused_any && ok "credit ran out after a tool ran: API paused" || bad "no pause file"
grep -q "API REFUSED (Credit balance is too low, rc=1).*not repeated" "$LOG" && ok "log says it was not repeated" || bad "log: $(cat "$LOG")"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$GOOD" FAKE_MENTION=1 bash "$CC" -p 2>/dev/null)
check "short answer that mentions 'Invalid API key': one call, no pause" "$OUT|$(calls)|$(paused_any && echo paused)" "The log shows Invalid API key in service X|1|"
reset
echo q | CLAUDE_CREDITO_KEY="$GOOD" FAKE_MENTION=1 FAKE_API_RC=1 bash "$CC" -p >/dev/null 2>&1; rc=$?
check "same answer with exit 1: still one call, no pause (the error is not from the API)" "$rc|$(calls)|$(paused_any && echo paused)" "1|1|"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p --output-format json 2>/dev/null)
check "json, refused before any turn: repeated on the subscription" "$OUT|$(calls)" "sub-ok [q]|2"
grep -q -- "--session-id" "$W/calls" && bad "json call got a --session-id" || ok "json call: arguments untouched"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$MIDLOW" bash "$CC" -p --output-format=json 2>/dev/null)
case "$OUT" in '{"type":"result"'*'"is_error":true'*) r=json ;; *) r="$OUT" ;; esac
check "json, credit ran out after a turn: not repeated, json returned as is" "$r|$(calls)" "json|1"
paused_any && ok "json, after a turn: API paused" || bad "no pause file"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p --verbose --output-format stream-json 2>/dev/null)
check "stream-json with a long init event, refused before any turn: repeated" "$OUT|$(calls)" "sub-ok [q]|2"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p --resume abc 2>/dev/null); rc=$?
check "caller's own session (--resume): no proof, so not repeated; error returned" "$OUT|$rc|$(calls)" "Credit balance is too low|1|1"
grep -q -- "--session-id" "$W/calls" && bad "--resume call got a --session-id" || ok "--resume: arguments untouched"
paused_any && ok "--resume: API paused" || bad "no pause file"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$LOW" FAKE_NO_TRANSCRIPT=1 bash "$CC" -p 2>/dev/null)
check "no transcript written: no proof, so not repeated" "$OUT|$(calls)" "Credit balance is too low|1"
reset
OUT=$(echo q | CLAUDE_CONFIG_DIR="$W/cfgdir" CLAUDE_CREDITO_KEY="$LOW" bash "$CC" -p 2>/dev/null)
check "transcript found under CLAUDE_CONFIG_DIR" "$OUT|$(calls)" "sub-ok [q]|2"

echo "== audit round 2"
reset
# AC-01: killing the wrapper also stops the claude it started
CLAUDE_CREDITO_KEY="$GOOD" FAKE_SLEEP=30 bash "$CC" -p x </dev/null >/dev/null 2>&1 & WP=$!
i=0; until [ -s "$W/pid" ] || [ $i -gt 50 ]; do sleep 0.1; i=$((i+1)); done
CP=$(cat "$W/pid" 2>/dev/null); kill -TERM $WP 2>/dev/null; wait $WP 2>/dev/null
i=0; while [ -n "$CP" ] && kill -0 "$CP" 2>/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done
if [ -n "$CP" ] && ! kill -0 "$CP" 2>/dev/null; then ok "AC-01: TERM to the wrapper reaches claude"; else bad "AC-01: claude $CP still running"; kill "$CP" 2>/dev/null; fi
rm -f "$W/pid"
reset
# AC-02: a tool input that holds "model":"<synthetic>" is still a real turn: not repeated
OUT=$(echo q | CLAUDE_CREDITO_KEY="$TOOLTEXT" bash "$CC" -p 2>/dev/null)
check "AC-02: real turn whose tool input names <synthetic>: not repeated" "$OUT|$(calls)" "Credit balance is too low|1"
reset
# AC-03: a stdin pipe that stays open and silent does not hang the wrapper (claude gives up on it)
mkfifo "$W/silent"; ( exec sleep 8 > "$W/silent" ) & SP=$!
start=$(date +%s)
OUT=$(CLAUDE_CREDITO_KEY="$GOOD" FAKE_STDIN_GIVEUP=1 bash "$CC" -p x < "$W/silent" 2>/dev/null)
el=$(( $(date +%s) - start )); kill $SP 2>/dev/null; wait $SP 2>/dev/null; rm -f "$W/silent"
if [ $el -lt 6 ]; then check "AC-03: open silent stdin: the wrapper returns when claude does" "$OUT" "api-ok []"; else bad "AC-03: took ${el}s: $OUT"; fi
reset
# stdin with data reaches claude through an anonymous pipe, never a named FIFO (the real claude hangs on one)
start=$(date +%s)
OUT=$(printf 'question' | CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p --output-format json 2>/dev/null)
el=$(( $(date +%s) - start ))
if [ $el -lt 4 ]; then check "stdin with data: claude gets it on an anonymous pipe and answers" "$(calls)|$(cut -d' ' -f2 "$W/calls")" "1|stdin=[question]"; else bad "stdin with data: took ${el}s (claude got a named FIFO): $OUT"; fi
reset
# AC-04: when the copy of stdin cannot be kept whole, claude still gets all of it and a refusal is not repeated
OUT=$(printf 'line1 line2' | CLAUDE_CREDITO_KEY="$LOW" CLAUDE_CREDITO_TEST_COPY_FAIL=1 bash "$CC" -p 2>/dev/null)
check "AC-04: copy failed: API call got all stdin; not repeated" "$(head -n 1 "$W/calls" | cut -d' ' -f2-3)|$(calls)" "stdin=[line1 line2]|1"
reset
# AC-07: the answer comes out byte for byte (no added newline, NUL kept), only the notice line removed
printf 'raw\0bytes, no final newline' > "$W/want"
CLAUDE_CREDITO_KEY="$GOOD" FAKE_RAW=1 bash "$CC" -p x </dev/null > "$W/got" 2>/dev/null
cmp -s "$W/got" "$W/want" && ok "AC-07: output kept byte for byte" || bad "AC-07: got $(od -c "$W/got" | head -n 2)"

echo "== key, config, status"
reset
OUT=$(echo "$GOOD" | bash "$CC" --credit-store-key); check "store the key from stdin" "$OUT" "key stored (ends in …good)"
F="$HOME/.config/claude-credito/key"
P=$(ls -l "$F" | cut -c1-10); check "key file is private" "$P" "-rw-------"
OUT=$(echo q | bash "$CC" -p 2>/dev/null); check "the stored key is used" "$OUT" "api-ok [q]"
rm -f "$F"; echo "do not touch" > "$W/target"; chmod 644 "$W/target"; ln -s "$W/target" "$F"
OUT=$(echo "$GOOD" | bash "$CC" --credit-store-key)
check "AC-06: a key file that is a link: the link is replaced, its target untouched" "$(cat "$W/target")|$([ -L "$F" ] && echo link)|$(ls -l "$F" | cut -c1-10)" "do not touch||-rw-------"
rm -f "$F"; (umask 022; echo old > "$F"); chmod 644 "$F"
echo "$GOOD" | bash "$CC" --credit-store-key >/dev/null; check "AC-06: an open key file ends private" "$(ls -l "$F" | cut -c1-10)" "-rw-------"
OUT=$(echo "not-a-key" | bash "$CC" --credit-store-key 2>&1); check "a wrong-looking key is refused" "$?|$OUT" "1|that is not a Console API key (it starts with sk-ant-)"
rm -f "$F"
OUT=$(CLAUDE_CREDITO_KEY_COMMAND="echo $LOW" bash "$CC" --credit-store-key </dev/null); check "store the key from a command" "$OUT" "key stored (ends in …-low)"
rm -f "$F"
OUT=$(bash "$CC" --credit-status); echo "$OUT" | grep -q "^key: NOT stored" && echo "$OUT" | grep -q "^pause: off" \
  && echo "$OUT" | grep -q "^claude: $W/fakebin/claude" && ok "status: no key, no pause, the claude it found" || bad "$OUT"
mkdir -p "$W/other" "$HOME/.config/claude-credito"
printf '#!/bin/sh\ncat >/dev/null\necho other-claude\n' > "$W/other/claude"; chmod +x "$W/other/claude"
printf '# comment\nCLAUDE_CREDITO_REAL="%s"\nPATH=/nope\nCLAUDE_CREDITO_PAUSE_S=7\n' "$W/other/claude" > "$HOME/.config/claude-credito/config"
OUT=$(echo q | bash "$CC" -p 2>/dev/null); check "config file: CLAUDE_CREDITO_REAL (other lines ignored)" "$OUT" "other-claude"
OUT=$(echo q | CLAUDE_CREDITO_REAL="$W/fakebin/claude" bash "$CC" -p 2>/dev/null); check "the environment wins over the config file" "$OUT" "sub-ok [q]"
rm -f "$HOME/.config/claude-credito/config"
OUT=$(PATH="/usr/bin:/bin" bash "$CC" -p x </dev/null 2>&1); check "no claude anywhere: clear error, exit 127" "$?|$OUT" "127|claude-credito: claude not found (install Claude Code or set CLAUDE_CREDITO_REAL)"
bash "$CC" --credit-help | grep -q "^Usage:" && ok "--credit-help prints the usage" || bad "no usage"
PV=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$R/.claude-plugin/plugin.json")
check "--credit-version matches plugin.json" "$(bash "$CC" --credit-version)" "claude-credito $PV"

echo "== install.sh and the shim"
reset
OUT=$(bash "$R/install.sh" --dry-run); [ ! -e "$HOME/.local/bin/claude-credito" ] && echo "$OUT" | grep -q "(dry-run)" && ! echo "$OUT" | grep -qE "^(installed|wrote|Next)" && ok "--dry-run writes nothing and says so" || bad "$OUT"
OUT=$(bash "$R/install.sh") || bad "install failed: $OUT"
[ -x "$HOME/.local/bin/claude-credito" ] && [ -x "$HOME/.local/share/claude-credito/shim/claude" ] && ok "installs the tool and the shim" || bad "$OUT"
cmp -s "$R/config.example" "$HOME/.config/claude-credito/config" && ok "starter config written" || bad "no starter config"
I1=$(ls -i "$HOME/.local/bin/claude-credito" | cut -d' ' -f1); bash "$R/install.sh" >/dev/null; I2=$(ls -i "$HOME/.local/bin/claude-credito" | cut -d' ' -f1)
[ "$I1" != "$I2" ] && [ -z "$(ls -A "$HOME/.local/bin" | grep -v '^claude-credito$')" ] && ok "a new install replaces the file by rename, and leaves no temporary file" || bad "inode $I1 -> $I2: $(ls -A "$HOME/.local/bin")"
echo "CLAUDE_CREDITO_PAUSE_S=9" > "$HOME/.config/claude-credito/config"; bash "$R/install.sh" >/dev/null
check "an existing config is never changed" "$(cat "$HOME/.config/claude-credito/config")" "CLAUDE_CREDITO_PAUSE_S=9"
rm -f "$HOME/.config/claude-credito/config"
# a script that calls a bare `claude`, with the shim first on PATH: the shim must not find itself
OUT=$(echo q | PATH="$HOME/.local/share/claude-credito/shim:$PATH" CLAUDE_CREDITO_KEY="$GOOD" claude -p 2>/dev/null)
check "shim first on PATH: goes through claude-credito to the real claude" "$OUT|$(calls)" "api-ok [q]|1"
# AC-05: an install folder with & | and $( ) in its name: the shim still runs the tool, nothing is executed
WEIRD="$W/we&ird|dir \$(touch $W/pwned)"
INSTALL_BIN_DIR="$WEIRD" bash "$R/install.sh" >/dev/null 2>&1
OUT=$(echo q | PATH="$HOME/.local/share/claude-credito/shim:$PATH" CLAUDE_CREDITO_KEY="$GOOD" claude -p 2>/dev/null)
check "AC-05: odd install folder: the shim reaches the tool" "$OUT|$([ -e "$W/pwned" ] && echo pwned)" "api-ok [q]|"
INSTALL_BIN_DIR="$WEIRD" bash "$R/install.sh" --uninstall >/dev/null 2>&1
bash "$R/install.sh" >/dev/null
OUT=$(bash "$R/install.sh" --uninstall); [ ! -e "$HOME/.local/bin/claude-credito" ] && [ ! -e "$HOME/.local/share/claude-credito/shim/claude" ] && ok "--uninstall removes both" || bad "$OUT"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
