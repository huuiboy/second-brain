#!/usr/bin/env bash
# Share ~/brain over SMB on the home LAN so Claude Code on Windows can use it.
# Run on ufinger from your normal user:  sudo bash setup-samba.sh
set -euo pipefail
U="${SUDO_USER:-}"
[ -n "$U" ] && [ "$U" != root ] || { echo "Run from your normal user with sudo:  sudo bash setup-samba.sh"; exit 1; }
HOME_DIR="$(getent passwd "$U" | cut -d: -f6)"
BRAIN="${BRAIN_DIR:-$HOME_DIR/brain}"
LAN="${LAN_CIDR:-10.168.168.0/24}"
[ -f "$BRAIN/MEMORY.md" ] || { echo "$BRAIN/MEMORY.md not found - run install.sh first"; exit 1; }

command -v smbd >/dev/null || { echo "==> Installing Samba"; apt-get update -qq && apt-get install -y samba; }

CONF=/etc/samba/smb.conf
[ -e "$CONF.bak-before-brain" ] || cp "$CONF" "$CONF.bak-before-brain"
if ! grep -q '^\[brain\]' "$CONF"; then
  echo "==> Adding [brain] share for $BRAIN (LAN $LAN only)"
  cat >> "$CONF" <<SHARE

[brain]
   comment = Claude Code second brain
   path = $BRAIN
   valid users = $U
   force user = $U
   read only = no
   browseable = yes
   create mask = 0664
   directory mask = 0775
   hosts allow = $LAN 127.0.0.1
   hosts deny = 0.0.0.0/0
   hide dot files = yes
   veto files = /.git/
SHARE
fi
testparm -s >/dev/null 2>&1 || { echo "smb.conf has an error - restoring backup"; cp "$CONF.bak-before-brain" "$CONF"; exit 1; }

if ! pdbedit -L 2>/dev/null | grep -q "^$U:"; then
  echo "==> Set a network-drive password for $U (Windows will ask for this once):"
  smbpasswd -a "$U"
fi
systemctl enable --now smbd >/dev/null 2>&1 || true
systemctl restart smbd

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  echo "==> Opening Samba in ufw for $LAN"; ufw allow from "$LAN" to any app Samba >/dev/null
fi

# Edits made from Windows don't trigger ufinger's SessionEnd hook, so auto-commit every 15 min.
if ! crontab -u "$U" -l 2>/dev/null | grep -q 'brain/.hooks/session-end.sh'; then
  echo "==> Adding 15-minute auto-commit cron for $U"
  (crontab -u "$U" -l 2>/dev/null; echo "*/15 * * * * $BRAIN/.hooks/session-end.sh") | crontab -u "$U" -
fi

IP="$(hostname -I | awk '{print $1}')"
echo
echo "Done. Share: \\\\$IP\\brain  (user: $U)"
echo "Next, on Windows run install-windows.ps1"
