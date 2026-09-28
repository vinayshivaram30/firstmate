#!/usr/bin/env bash
# Adversarial drive: two sessions racing for the same offerline ticket copy, plus
# the unusable-copy refusals, all against the real bin/fm-spawn.sh.
set -u
cd "${1:?worktree}"
. tests/fixtures.sh
CASE=$(mktemp -d "${TMPDIR:-/tmp}/adopt-collide.XXXXXX")
PROJECT=$CASE/project; ORIGIN=$CASE/origin.git
CLAIM=$PROJECT/.claude/worktrees/issue-7
mk_home() { local h=$1 id=$2; mkdir -p "$h"/{state,config,projects,data}
  printf 'codex\n' > "$h/config/crew-harness"; fm_test_spawn_brief "$h" "$id" "ticket $id"
  touch "$h/state/.last-watcher-beat"; }
mk_home "$CASE/home-a" issue-7
mk_home "$CASE/home-b" issue-7b
git init --quiet -b main "$PROJECT"
printf 'base\n' > "$PROJECT/README.md"
printf '.claude/worktrees/\n.claude/settings.local.json\n' > "$PROJECT/.gitignore"
git -C "$PROJECT" add README.md .gitignore
git -C "$PROJECT" -c user.name=t -c user.email=t@e.invalid commit -qm initial
git clone --quiet --bare "$PROJECT" "$ORIGIN"
git -C "$PROJECT" remote add origin "file://$ORIGIN"
git -C "$PROJECT" fetch --quiet origin
git -C "$PROJECT" worktree add --quiet "$CLAIM" -b issue-7
CLAIM=$(cd "$CLAIM" && pwd -P)
FAKEBIN=$(fm_test_make_spawn_fakebin "$CASE/fake")
run() { local h=$1 id=$2 path=$3; shift 3
  fm_test_run_spawn "$h" "$path" "$FAKEBIN" "$id" "$PROJECT" --mode no-mistakes --yolo off --adopt-worktree "$path"; }
show() { printf '%s\n' "$1" | sed "s#$CASE#\$CASE#g"; }

echo "== session A adopts the claimed copy =="
out=$(run "$CASE/home-a" issue-7 "$CLAIM"); echo "exit=$?"; show "$out" | tail -1

echo
echo "== session B (separate firstmate home) tries the same copy =="
out=$(run "$CASE/home-b" issue-7b "$CLAIM"); echo "exit=$?"; show "$out" | tail -3
echo "session B published a record: $([ -e "$CASE/home-b/state/issue-7b.meta" ] && echo YES || echo no)"

echo
echo "== session B tries a symlinked spelling of the same copy =="
ln -s "$CLAIM" "$CASE/alias"
out=$(run "$CASE/home-b" issue-7b "$CASE/alias"); echo "exit=$?"; show "$out" | tail -2

echo
echo "== adopting the project primary checkout instead of a worktree =="
out=$(run "$CASE/home-b" issue-7b "$PROJECT"); echo "exit=$?"; show "$out" | tail -2

echo
echo "== adopting a copy with uncommitted changes =="
git -C "$PROJECT" worktree add --quiet "$PROJECT/.claude/worktrees/issue-9" -b issue-9
DIRTY=$(cd "$PROJECT/.claude/worktrees/issue-9" && pwd -P)
printf 'wip\n' >> "$DIRTY/README.md"
out=$(run "$CASE/home-b" issue-7b "$DIRTY"); echo "exit=$?"; show "$out" | tail -2

echo
echo "== adopting a path that does not exist =="
out=$(run "$CASE/home-b" issue-7b "$CASE/nope"); echo "exit=$?"; show "$out" | tail -2
rm -rf "$CASE"
