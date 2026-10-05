#!/bin/bash
# clipsync client installer. The hub serves this file with the token and its
# own address filled in, so on each Mac you only run:
#   curl -fsS "http://<hub-tailscale-ip>:8377/install?t=TOKEN" | bash
set -e
HUB="__HUB__"
TOKEN="__TOKEN__"
LABEL="local.clipsync"
mkdir -p "$HOME/.local/bin" "$HOME/.config/clipsync" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
printf '%s' "$TOKEN" > "$HOME/.config/clipsync/token"
printf '%s' "$HUB" > "$HOME/.config/clipsync/hub"
chmod 600 "$HOME/.config/clipsync/token"
curl -fsS "$HUB/bin?t=$TOKEN" -o "$HOME/.local/bin/clipsync"
chmod +x "$HOME/.local/bin/clipsync"
P="$HOME/Library/LaunchAgents/$LABEL.plist"
cat > "$P" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$HOME/.local/bin/clipsync</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/clipsync.log</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$P"
echo "clipsync installed and running."
