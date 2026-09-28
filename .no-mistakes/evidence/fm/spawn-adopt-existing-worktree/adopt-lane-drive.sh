#!/usr/bin/env bash
# Manual end-to-end drive of the offerline ticket lane this change exists for:
#   captain claims .claude/worktrees/issue-7 -> fm-spawn.sh --adopt-worktree
#   -> record + claim + preserved creator wiring -> teardown hands the copy back.
set -u
ROOT_WT=${1:?worktree}
cd "$ROOT_WT"
. tests/fixtures.sh
CASE=$(mktemp -d "${TMPDIR:-/tmp}/adopt-lane.XXXXXX")
HOME_DIR=$CASE/home; PROJECT=$CASE/project; ORIGIN=$CASE/origin.git
CLAIM=$PROJECT/.claude/worktrees/issue-7
ID=issue-7
mkdir -p "$HOME_DIR"/{state,config,projects,data}
printf 'codex\n' > "$HOME_DIR/config/crew-harness"
fm_test_spawn_brief "$HOME_DIR" "$ID" "take offerline ticket 7"
touch "$HOME_DIR/state/.last-watcher-beat"

git init --quiet -b main "$PROJECT"
printf 'base\n' > "$PROJECT/README.md"
printf '.claude/worktrees/\n.claude/settings.local.json\n' > "$PROJECT/.gitignore"
git -C "$PROJECT" add README.md .gitignore
git -C "$PROJECT" -c user.name=t -c user.email=t@e.invalid commit -qm initial
git clone --quiet --bare "$PROJECT" "$ORIGIN"
git -C "$PROJECT" remote add origin "file://$ORIGIN"
git -C "$PROJECT" fetch --quiet origin

echo "== captain claims the ticket the way offerline AGENTS.md mandates =="
git -C "$PROJECT" worktree add "$CLAIM" -b issue-7
CLAIM=$(cd "$CLAIM" && pwd -P)

echo
echo "== the creator's own Claude settings already live in that copy =="
mkdir -p "$CLAIM/.claude"
printf '{"creator":"mac-mini-captain"}\n' > "$CLAIM/.claude/settings.local.json"
CREATOR_SUM=$(shasum "$CLAIM/.claude/settings.local.json" | awk '{print $1}')
cat "$CLAIM/.claude/settings.local.json"

FAKEBIN=$(fm_test_make_spawn_fakebin "$CASE/fake")
cat > "$FAKEBIN/treehouse" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TREEHOUSE_LOG"
exit 0
SH
chmod +x "$FAKEBIN/treehouse"
export FM_TREEHOUSE_LOG=$CASE/treehouse.log
: > "$FM_TREEHOUSE_LOG"

echo
echo "== dispatch: fm-spawn.sh --adopt-worktree \$CLAIM =="
out=$(fm_test_run_spawn "$HOME_DIR" "$CLAIM" "$FAKEBIN" "$ID" "$PROJECT" \
  --mode no-mistakes --yolo off --adopt-worktree "$CLAIM"); rc=$?
printf '%s\n' "$out" | sed "s#$CASE#\$CASE#g"
echo "spawn exit: $rc"

echo
echo "== recorded task metadata =="
sed "s#$CASE#\$CASE#g" "$HOME_DIR/state/$ID.meta"

GITDIR=$(git -C "$CLAIM" rev-parse --absolute-git-dir)
echo
echo "== owner claim written on the adopted copy =="
sed "s#$CASE#\$CASE#g" "$GITDIR/fm-adopted-owner"

echo
echo "== treehouse was never asked for a pool slot =="
echo "treehouse invocations: $(wc -l < "$FM_TREEHOUSE_LOG" | tr -d ' ')"

echo
echo "== creator's settings.local.json preserved, firstmate's wiring armed in place =="
echo "-- store copy (creator's original):"
cat "$GITDIR/fm-adopted-wiring/.claude/settings.local.json"
echo "-- live copy now armed by firstmate (first 3 lines):"
head -3 "$CLAIM/.claude/settings.local.json"

echo
echo "== an unrelated session of the creator is working in that copy =="
( cd "$CLAIM" && exec sleep 300 ) & UNRELATED=$!
sleep 1
echo "unrelated pid $UNRELATED alive: $(kill -0 "$UNRELATED" 2>/dev/null && echo yes || echo no)"

echo
echo "== work lands on origin, then teardown =="
git -C "$CLAIM" -c user.name=t -c user.email=t@e.invalid commit -q --allow-empty -m 'ticket 7 work'
git -C "$CLAIM" push --quiet origin issue-7
cat > "$FAKEBIN/no-mistakes" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "axi status"*) printf '%s\n' "${FM_FAKE_AXI_STATUS:-}" ;;
  "axi abort"*) printf '%s\n' "$*" >> "${FM_FAKE_NM_ABORT_LOG:-/dev/null}" ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/no-mistakes"
cat > "$FAKEBIN/gh-axi" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "pr list") printf '%s\n' "count: 0 (showing first 0)" "pull_requests[]: []"; exit 0 ;;
  "pr view") echo "error: pull request not found" >&2; exit 1 ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/gh-axi"
out=$(FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" HOME="$HOME_DIR/user-home" \
  FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
  FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
  FM_FAKE_NM_ABORT_LOG="$CASE/nm-abort.log" \
  PATH="$FAKEBIN:$PATH" bash bin/fm-teardown.sh "$ID" 2>&1); rc=$?
printf '%s\n' "$out" | sed "s#$CASE#\$CASE#g"
echo "teardown exit: $rc"

echo
echo "== after teardown =="
echo "copy still present: $([ -d "$CLAIM" ] && echo yes || echo no)"
echo "branch still checked out: $(git -C "$CLAIM" symbolic-ref --short HEAD 2>/dev/null)"
echo "creator's settings.local.json byte-identical: $([ "$(shasum "$CLAIM/.claude/settings.local.json" | awk '{print $1}')" = "$CREATOR_SUM" ] && echo yes || echo NO)"
echo "owner claim released: $([ -e "$GITDIR/fm-adopted-owner" ] && echo NO || echo yes)"
echo "preserve store removed: $([ -e "$GITDIR/fm-adopted-wiring" ] && echo NO || echo yes)"
echo "unrelated creator process still alive: $(kill -0 "$UNRELATED" 2>/dev/null && echo yes || echo NO)"
echo "treehouse return calls: $(grep -c return "$FM_TREEHOUSE_LOG" || true)"
kill "$UNRELATED" 2>/dev/null
rm -rf "$CASE"
