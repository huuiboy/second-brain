# Connects Claude Code on this Windows PC (CLI + desktop app) to the second brain on ufinger.
# Run in a NORMAL (not admin) PowerShell window:
#   powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
param(
  [string]$Server = "10.168.168.194",
  [string]$Share  = "brain",
  [string]$User   = "huuiboy",
  [string]$Drive  = "B:"
)
$ErrorActionPreference = "Stop"
function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function WriteUtf8($path, $text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false)) }

# 1. Map the network drive (persists across reboots) -----------------------
if (-not (Test-Path "$Drive\MEMORY.md")) {
  Say "Mapping $Drive to \\$Server\$Share - enter the network-drive password you set on ufinger"
  net use $Drive "\\$Server\$Share" /user:$User /persistent:yes
  if ($LASTEXITCODE -ne 0) { throw "Could not map $Drive. Is setup-samba.sh done on ufinger and are you on the home network?" }
}
if (-not (Test-Path "$Drive\MEMORY.md")) { throw "$Drive is mapped but MEMORY.md is missing - check the share path on ufinger." }
Say "Brain reachable at $Drive"

$Claude = Join-Path $env:USERPROFILE ".claude"
New-Item -ItemType Directory -Force (Join-Path $Claude "commands") | Out-Null
$B = "$Drive/"   # forward-slash form for prompts

# 2. SessionStart hook: inject MEMORY.md + current project note --------------
$hook = @'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$Brain = "__DRIVE__"
$cwd = $null
try { $cwd = ([Console]::In.ReadToEnd() | ConvertFrom-Json).cwd } catch {}
if (-not $cwd) { $cwd = (Get-Location).Path }
if (-not (Test-Path "$Brain\MEMORY.md")) {
  "(Second brain at $Brain is not reachable - not on the home network? Continuing without memory this session.)"
  exit 0
}
$proj = Split-Path -Leaf $cwd
try { $top = git -C $cwd rev-parse --show-toplevel 2>$null; if ($top) { $proj = Split-Path -Leaf $top } } catch {}
"<second-brain path=""$Brain/"">"
Get-Content -Raw -Encoding UTF8 "$Brain\MEMORY.md"
$pn = Join-Path "$Brain\" "projects\$proj.md"
if (Test-Path $pn) { ""; "## Project note: projects/$proj.md"; Get-Content -Raw -Encoding UTF8 $pn }
else { ""; "(No project note for '$proj' yet - create projects/$proj.md from projects/_template.md if this is a real project.)" }
"</second-brain>"
'@
$hookPath = Join-Path $Claude "brain-session-start.ps1"
WriteUtf8 $hookPath ($hook -replace '__DRIVE__', $Drive)
$cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + ($hookPath -replace '\\', '/') + '"'

# 3. Register the hook in settings.json (merged, backed up) ------------------
Say "Registering SessionStart hook"
$settingsPath = Join-Path $Claude "settings.json"
$s = $null
if (Test-Path $settingsPath) {
  Copy-Item $settingsPath "$settingsPath.bak" -Force
  $raw = Get-Content -Raw $settingsPath
  if ($raw -and $raw.Trim()) { $s = $raw | ConvertFrom-Json }
}
if (-not $s) { $s = New-Object PSObject }
if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
if (-not $s.hooks.PSObject.Properties['SessionStart']) { $s.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @() }
$already = @($s.hooks.SessionStart | ForEach-Object { $_.hooks } | Where-Object { $_.command -eq $cmd })
if ($already.Count -eq 0) {
  $entry = New-Object PSObject -Property @{ hooks = @( (New-Object PSObject -Property @{ type = 'command'; command = $cmd }) ) }
  $s.hooks.SessionStart = @($s.hooks.SessionStart) + @($entry)
}
WriteUtf8 $settingsPath ($s | ConvertTo-Json -Depth 32)

# 4. Global CLAUDE.md instructions ------------------------------------------
Say "Adding second-brain instructions to $Claude\CLAUDE.md"
$block = @"
<!-- second-brain:start -->
# Second brain (persistent memory)
My long-term memory lives on ufinger, mapped on this PC as ``$B`` (plain markdown, also shown in Obsidian).
At session start a hook injects ``MEMORY.md`` plus the note for the current project.
If $Drive is unreachable (I'm away from home), say so once and carry on.

- **Read**: before non-trivial work, check the relevant files in ``$B`` (projects/, decisions/, lessons/, me/).
- **Write back** without being asked when you learn something durable:
  a preference or correction from me -> me/preferences.md; a mistake + fix -> lessons/lessons.md;
  an architectural choice -> decisions/; project status/TODOs -> projects/<name>.md. Keep MEMORY.md a short index.
- Link notes with Obsidian [[wikilinks]] so they show in the graph.
- Before ending a substantial session, offer to run /reflect.
- Never store secrets, API keys or passwords in the brain.
<!-- second-brain:end -->
"@
$mdPath = Join-Path $Claude "CLAUDE.md"
$md = ""; if (Test-Path $mdPath) { $md = [IO.File]::ReadAllText($mdPath) }
$re = '(?s)<!-- second-brain:start -->.*?<!-- second-brain:end -->'
if ($md -match $re) { $md = [regex]::Replace($md, $re, { param($m) $block }) }
else { $md = ($md.TrimEnd() + "`n`n" + $block + "`n").TrimStart() }
WriteUtf8 $mdPath $md

# 5. Slash commands -----------------------------------------------------------
Say "Installing /remember, /recall, /reflect"
WriteUtf8 (Join-Path $Claude "commands\remember.md") @"
---
description: Save something to the second brain
argument-hint: <what to remember>
---
Save this to my second brain (the folder $B) - item: `$ARGUMENTS

Pick the right home (me/preferences.md, lessons/lessons.md, projects/<name>.md,
decisions/YYYY-MM-DD-title.md, or inbox.md if unsure). Write it concisely and dated.
If it's a durable preference or key fact, also add a one-line pointer to MEMORY.md.
Don't duplicate existing entries - update them instead. Confirm what you saved in one line.
"@
WriteUtf8 (Join-Path $Claude "commands\recall.md") @"
---
description: Search the second brain
argument-hint: <topic>
---
Search my second brain at $B for: `$ARGUMENTS
Use the Grep and Glob tools across the whole vault (include sessions/ and decisions/), read the
best matches, and answer with what I know about it, citing file paths.
"@
WriteUtf8 (Join-Path $Claude "commands\reflect.md") @"
---
description: Write this session's learnings back to the second brain
---
Review this session and update my second brain (the folder $B) as follows.
1. Append a 3-6 line summary to sessions/YYYY-MM.md (date, machine: Windows PC, project, what was done, what's next).
2. Update projects/<project>.md (status, TODOs, gotchas). Create it from _template.md if missing.
3. Add any new lessons to lessons/lessons.md and any significant decisions to decisions/.
4. Add newly learned durable preferences to me/preferences.md.
5. File anything in inbox.md into its proper place.
6. Keep MEMORY.md a tight index (<150 lines): add pointers, prune stale lines.
Then list what you changed in a few bullets.
"@

Say "Done!"
Write-Host ""
Write-Host "Restart the Claude desktop app (or open a new 'claude' terminal session)."
Write-Host "Test: ask Claude 'what's in my second brain?' - it should answer from MEMORY.md."
