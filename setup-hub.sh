#!/bin/bash
# Run once on the always-on Mac that will be the hub. Builds the client,
# creates a shared token, starts the hub at login, and installs the client on
# this Mac too. Prints the one-line command to run on your other Macs.
set -e
cd "$(dirname "$0")"
DIR="$(pwd)"
TS="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
IP="$("$TS" ip -4 | head -1)"
[ -n "$IP" ] || { echo "Tailscale is not running on this Mac."; exit 1; }
PY="$(command -v python3)"

swiftc -O -target arm64-apple-macos14.0 clipsync.swift -o clipsync
mkdir -p "$HOME/.config/clipsync" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
[ -s "$HOME/.config/clipsync/token" ] || "$PY" -c "import secrets;print(secrets.token_urlsafe(24),end='')" > "$HOME/.config/clipsync/token"
chmod 600 "$HOME/.config/clipsync/token"
TOKEN="$(cat "$HOME/.config/clipsync/token")"

LABEL="local.clipsync-hub"
P="$HOME/Library/LaunchAgents/$LABEL.plist"
cat > "$P" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$DIR/hub.py</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/clipsync-hub.log</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$P"
sleep 1
curl -fsS "http://$IP:8377/install?t=$TOKEN" | bash
echo
echo "Hub running. On each other Mac in your tailnet, run:"
echo "  curl -fsS \"http://$IP:8377/install?t=$TOKEN\" | bash"
