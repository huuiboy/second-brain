#!/usr/bin/env bash
# Second brain installer for Claude Code (run on ufinger as your normal user).
# Safe to re-run: never overwrites notes you've already written.
set -euo pipefail

BRAIN="${BRAIN_DIR:-$HOME/brain}"
CLAUDE_DIR="$HOME/.claude"
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
write_if_missing() { [ -e "$1" ] || { mkdir -p "$(dirname "$1")"; cat > "$1"; return 0; }; cat >/dev/null; }

command -v git >/dev/null || { echo "git is required (sudo apt install git)"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required (sudo apt install python3)"; exit 1; }

say "Creating vault at $BRAIN"
mkdir -p "$BRAIN"/{me,projects,decisions,lessons,sessions,.hooks}

write_if_missing "$BRAIN/MEMORY.md" <<'EOF'
# MEMORY — loaded into every Claude Code session
<!-- Keep this file SHORT (under ~150 lines). It's the index, not the archive.
     Details live in the linked files; Claude reads them when relevant. -->

## About me
- See me/profile.md and me/preferences.md

## Standing preferences (most important first)
- (Claude: add durable preferences here as you learn them)

## Active projects
- (Claude: one line per project -> projects/<name>.md)

## Recent key decisions
- (Claude: newest first, link to decisions/ file)

## Lessons / gotchas
- (Claude: one-liners, details in lessons/lessons.md)
EOF

write_if_missing "$BRAIN/me/profile.md" <<'EOF'
# Profile
- Name:
- Role / what I work on:
- Main machine: ufinger (Linux server)
- Languages & stacks I use:
- GitHub: huuiboy
EOF

write_if_missing "$BRAIN/me/preferences.md" <<'EOF'
# Preferences
## How I like Claude to work
-
## Code style
-
## Things to never do
-
EOF

write_if_missing "$BRAIN/lessons/lessons.md" <<'EOF'
# Lessons learned
<!-- Format: - YYYY-MM-DD [project] What happened -> what to do next time -->
EOF

write_if_missing "$BRAIN/projects/_template.md" <<'EOF'
# <project name>
- Path on ufinger:
- Repo:
- What it is:
- Stack:
- How to run / test:
## Current status
## Open TODOs
## Architecture notes
## Gotchas
EOF

write_if_missing "$BRAIN/decisions/README.md" <<'EOF'
# Decisions
One file per significant decision: `YYYY-MM-DD-short-title.md`
with Context / Decision / Why / Alternatives considered.
EOF

write_if_missing "$BRAIN/sessions/README.md" <<'EOF'
# Session log
`/reflect` appends a short summary per session to `YYYY-MM.md`.
EOF

write_if_missing "$BRAIN/inbox.md" <<'EOF'
# Inbox
Quick captures. `/reflect` files these into the right place.
EOF

# --- hooks ---------------------------------------------------------------
cat > "$BRAIN/.hooks/session-start.sh" <<'EOF'
#!/usr/bin/env bash
# Injects MEMORY.md (and matching project note) into every Claude Code session.
BRAIN="${BRAIN_DIR:-$HOME/brain}"
input="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("cwd",""))
except Exception: print("")' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"
proj="$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")")"

echo "<second-brain path=\"$BRAIN\">"
cat "$BRAIN/MEMORY.md" 2>/dev/null
if [ -f "$BRAIN/projects/$proj.md" ]; then
  echo; echo "## Project note: projects/$proj.md"; cat "$BRAIN/projects/$proj.md"
else
  echo; echo "(No project note for '$proj' yet — create projects/$proj.md from projects/_template.md if this is a real project.)"
fi
echo "</second-brain>"
EOF

cat > "$BRAIN/.hooks/session-end.sh" <<'EOF'
#!/usr/bin/env bash
# Commits any brain changes at the end of each session (and pushes if a remote exists).
BRAIN="${BRAIN_DIR:-$HOME/brain}"
cd "$BRAIN" 2>/dev/null || exit 0
git add -A >/dev/null 2>&1
git diff --cached --quiet && exit 0
git commit -qm "brain: auto-save $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1
git remote | grep -q . && (git push -q >/dev/null 2>&1 &)
exit 0
EOF
sed -i "s|^BRAIN=.*|BRAIN=\"$BRAIN\"|" "$BRAIN/.hooks/"*.sh
chmod +x "$BRAIN/.hooks/"*.sh

# --- git -------------------------------------------------------------------
if [ ! -d "$BRAIN/.git" ]; then
  say "Initialising git history for the vault"
  git -C "$BRAIN" init -q
fi
# Make sure auto-commits work even if git has no global identity on this machine
git -C "$BRAIN" config user.name  >/dev/null || git -C "$BRAIN" config user.name  "brain"
git -C "$BRAIN" config user.email >/dev/null || git -C "$BRAIN" config user.email "brain@$(hostname)"
if ! git -C "$BRAIN" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$BRAIN" add -A && git -C "$BRAIN" commit -qm "brain: initial vault"
fi

# --- slash commands -------------------------------------------------------
say "Installing /remember, /recall, /reflect commands"
mkdir -p "$CLAUDE_DIR/commands"
cat > "$CLAUDE_DIR/commands/remember.md" <<EOF
---
description: Save something to the second brain
argument-hint: <what to remember>
---
Save this to my second brain at $BRAIN: \$ARGUMENTS

Pick the right home (me/preferences.md, lessons/lessons.md, projects/<name>.md,
decisions/YYYY-MM-DD-title.md, or inbox.md if unsure). Write it concisely and dated.
If it's a durable preference or key fact, also add a one-line pointer to MEMORY.md.
Don't duplicate existing entries — update them instead. Confirm what you saved in one line.
EOF

cat > "$CLAUDE_DIR/commands/recall.md" <<EOF
---
description: Search the second brain
argument-hint: <topic>
---
Search my second brain at $BRAIN for: \$ARGUMENTS
Use grep -ril / rg across the vault (include sessions/ and decisions/), read the
best matches, and answer with what I know about it, citing file paths.
EOF

cat > "$CLAUDE_DIR/commands/reflect.md" <<EOF
---
description: Write this session's learnings back to the second brain
---
Review this session and update my second brain at $BRAIN:
1. Append a 3-6 line summary to sessions/\$(date +%Y-%m).md (date, project, what was done, what's next).
2. Update projects/<project>.md (status, TODOs, gotchas). Create it from _template.md if missing.
3. Add any new lessons to lessons/lessons.md and any significant decisions to decisions/.
4. Add newly learned durable preferences to me/preferences.md.
5. File anything in inbox.md into its proper place.
6. Keep MEMORY.md a tight index (<150 lines): add pointers, prune stale lines.
Then list what you changed in a few bullets.
EOF

# --- global CLAUDE.md ------------------------------------------------------
say "Adding second-brain instructions to $CLAUDE_DIR/CLAUDE.md"
touch "$CLAUDE_DIR/CLAUDE.md"
python3 - "$CLAUDE_DIR/CLAUDE.md" "$BRAIN" <<'PY'
import sys, re
path, brain = sys.argv[1], sys.argv[2]
block = f"""<!-- second-brain:start -->
# Second brain (persistent memory)
My long-term memory lives in `{brain}` (plain markdown, git-versioned).
At session start a hook injects `MEMORY.md` plus the note for the current project.

- **Read**: before non-trivial work, check the relevant files in `{brain}`
  (projects/, decisions/, lessons/). Search with `grep -ril <term> {brain}`.
- **Write back** without being asked when you learn something durable:
  a preference or correction from me -> me/preferences.md;
  a mistake + fix -> lessons/lessons.md; an architectural choice -> decisions/;
  project status/TODOs -> projects/<name>.md. Keep MEMORY.md a short index.
- Before ending a substantial session, offer to run /reflect.
- Link notes with Obsidian [[wikilinks]] (e.g. [[projects/dropfinder]]) so they show in the graph.
- Never store secrets, API keys or passwords in the brain.
<!-- second-brain:end -->"""
text = open(path).read()
pat = re.compile(r"<!-- second-brain:start -->.*?<!-- second-brain:end -->", re.S)
text = pat.sub(block, text) if pat.search(text) else (text.rstrip() + "\n\n" + block + "\n").lstrip()
open(path, "w").write(text)
PY

# --- settings.json hooks (merged, not overwritten) -------------------------
say "Registering SessionStart / SessionEnd hooks in $CLAUDE_DIR/settings.json"
python3 - "$CLAUDE_DIR/settings.json" "$BRAIN" <<'PY'
import sys, json, os, shutil
path, brain = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path) and os.path.getsize(path):
    shutil.copy(path, path + ".bak")
    data = json.load(open(path))
hooks = data.setdefault("hooks", {})
def ensure(event, cmd):
    groups = hooks.setdefault(event, [])
    for g in groups:
        for h in g.get("hooks", []):
            if h.get("command") == cmd: return
    groups.append({"hooks": [{"type": "command", "command": cmd}]})
ensure("SessionStart", f"{brain}/.hooks/session-start.sh")
ensure("SessionEnd",   f"{brain}/.hooks/session-end.sh")
json.dump(data, open(path, "w"), indent=2)
PY

say "Done!"
cat <<EOF

Your second brain is at: $BRAIN
Next steps:
  1. Fill in $BRAIN/me/profile.md and me/preferences.md (or just tell Claude and run /remember).
  2. Start claude in any project:  cd ~/some-project && claude
     - memory is injected automatically at session start
     - /remember <fact>   save something
     - /recall <topic>    search the brain
     - /reflect           write the session's learnings back
  3. Optional: open $BRAIN as an Obsidian vault to browse it.
EOF
