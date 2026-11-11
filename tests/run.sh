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
PRE="sk-ant-"; GOOD="${PRE}test-good"; LOW="${PRE}test-low"; WRONG="${PRE}test-wrong"   # not real keys
LOG="$HOME/.local/state/claude-credito/claude-credito.log"
PAUSE="$HOME/.local/state/claude-credito/paused"

cat > "$W/fakebin/claude" <<'EOF'
#!/bin/sh
# fake claude: records each call and answers by the key it was given
in="$(cat)"
echo "key=${ANTHROPIC_API_KEY:-none} stdin=[$in] args=$*" >> "$FAKE_DIR/calls"
case "${ANTHROPIC_API_KEY:-}" in
  "")     echo "sub-ok [$in]"; echo "sub-err" >&2; exit "${FAKE_SUB_RC:-0}" ;;
  *good)  echo "⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY is set"
          if [ -n "${FAKE_BIG:-}" ]; then head -c 7000 /dev/zero | tr '\0' x; echo " Invalid API key"; fi
          echo "api-ok [$in]"; echo "api-err" >&2; exit "${FAKE_API_RC:-0}" ;;
  *low)   echo "Credit balance is too low"; exit 1 ;;
  *)      echo "Invalid API key · Fix external API key"; exit 0 ;;
esac
EOF
chmod +x "$W/fakebin/claude"
calls() { if [ -f "$W/calls" ]; then wc -l < "$W/calls" | tr -d ' '; else echo 0; fi; }
reset() { rm -f "$W/calls" "$PAUSE" "$LOG"; }
cd "$W/work" || exit 1

echo "== which call uses the API"
reset
OUT=$(CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" "hello" </dev/null 2>/dev/null)
check "no -p: plain claude, no key" "$OUT|$(cat "$W/calls")" "sub-ok []|key=none stdin=[] args=hello"
reset
OUT=$(echo "question" | CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p --model x 2>"$W/err")
check "-p with a key: API answer, notice line removed" "$OUT" "api-ok [question]"
check "-p with a key: stderr kept" "$(cat "$W/err")" "api-err"
check "-p with a key: one call, with the key and the same arguments" "$(cat "$W/calls")" "key=$GOOD stdin=[question] args=-p --model x"
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
[ -f "$PAUSE" ] && ok "pause file written" || bad "no pause file"
grep -q "API REFUSED (Credit balance is too low, rc=1)" "$LOG" && grep -q "subscription rc=0" "$LOG" && ok "log lines: refused, subscription" || bad "log: $(cat "$LOG")"
OUT=$(echo q | CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p 2>/dev/null)
check "paused: straight to the subscription, even with a good key" "$OUT|$(calls)" "sub-ok [q]|3"
OUT=$(CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" --credit-status); echo "$OUT" | grep -q "^pause: on since" && ok "status shows the pause" || bad "$OUT"
OUT=$(echo q | CLAUDE_CREDITO_PAUSE_S=0 CLAUDE_CREDITO_KEY="$GOOD" bash "$CC" -p 2>/dev/null)
check "pause over: API again" "$OUT" "api-ok [q]"
[ -f "$PAUSE" ] && bad "pause file still there" || ok "expired pause file removed"
: > "$PAUSE"; OUT=$(bash "$CC" --credit-resume); [ ! -f "$PAUSE" ] && check "--credit-resume ends the pause" "$OUT" "pause ended"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$WRONG" bash "$CC" -p 2>/dev/null)
check "invalid key answered with exit 0: still seen as a refusal" "$OUT|$(calls)" "sub-ok [q]|2"
reset
echo q | CLAUDE_CREDITO_KEY="$LOW" FAKE_SUB_RC=4 bash "$CC" -p >/dev/null 2>&1; check "after a refusal the subscription's exit code is returned" "$?" "4"
reset
OUT=$(echo q | CLAUDE_CREDITO_KEY="$GOOD" FAKE_BIG=1 bash "$CC" -p 2>/dev/null | tail -n 1)
check "a long answer that mentions 'Invalid API key' is not a refusal" "$OUT|$(calls)" "api-ok [q]|1"

echo "== key, config, status"
reset
OUT=$(echo "$GOOD" | bash "$CC" --credit-store-key); check "store the key from stdin" "$OUT" "key stored (ends in …good)"
F="$HOME/.config/claude-credito/key"
P=$(ls -l "$F" | cut -c1-10); check "key file is private" "$P" "-rw-------"
OUT=$(echo q | bash "$CC" -p 2>/dev/null); check "the stored key is used" "$OUT" "api-ok [q]"
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
OUT=$(bash "$R/install.sh" --uninstall); [ ! -e "$HOME/.local/bin/claude-credito" ] && [ ! -e "$HOME/.local/share/claude-credito/shim/claude" ] && ok "--uninstall removes both" || bad "$OUT"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
