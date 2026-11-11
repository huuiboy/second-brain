# second-brain

Persistent memory ("second brain") for Claude Code on **ufinger**, browsable in Obsidian.

## Install (on ufinger, as your normal user — not root)

```bash
git clone https://github.com/huuiboy/second-brain.git ~/second-brain
cd ~/second-brain
bash install.sh                      # creates ~/brain + Claude Code hooks & commands
cp .env.example .env
sed -i "s/^PUID=.*/PUID=$(id -u)/; s/^PGID=.*/PGID=$(id -g)/" .env
nano .env                            # set OBSIDIAN_PASSWORD and TZ
docker compose up -d                 # Obsidian at https://10.168.168.194:3001
```

In Obsidian: **Open folder as vault → `/config/brain`**.

## What you get
- `~/brain/` — markdown vault (git-versioned). `MEMORY.md` is the short index loaded into every session.
- SessionStart hook injects `MEMORY.md` + the current project's note; SessionEnd hook auto-commits.
- Slash commands: `/remember <fact>`, `/recall <topic>`, `/reflect`.
- Global `~/.claude/CLAUDE.md` section telling Claude to read and write the brain.

## Use it from Claude Code on a Windows PC (home LAN)
1. On ufinger: `sudo bash setup-samba.sh` — shares `~/brain` as `\\10.168.168.194\brain` (LAN only),
   sets a network-drive password, and adds a 15-min auto-commit cron.
2. On Windows, in a normal (non-admin) PowerShell, from the folder holding `install-windows.ps1`:
   `powershell -ExecutionPolicy Bypass -File .\install-windows.ps1`
   — maps the brain as `B:`, adds a SessionStart hook, `~/.claude/CLAUDE.md` instructions and
   `/remember` `/recall` `/reflect` commands.
3. Restart the Claude desktop app. Ask "what's in my second brain?" to test.

## Always-on Remote Control (optional)
```bash
sudo loginctl enable-linger $USER
tmux new -d -s claude-rc 'cd ~ && claude remote-control'
(crontab -l 2>/dev/null; echo "@reboot tmux new -d -s claude-rc 'cd ~ && claude remote-control'") | crontab -
```

## Security
Keep port 3001 on the LAN — the Obsidian web UI gives root inside the container. Use Tailscale/VPN for remote access.
Never put secrets in the brain. `.env` is git-ignored.
