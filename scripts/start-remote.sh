#!/usr/bin/env bash
# Keep a Claude Code Remote Control server running for the Jarvis vault.
# Run it inside tmux so it survives your SSH session closing:
#
#   tmux new -s jarvis
#   bash scripts/start-remote.sh
#   (detach with Ctrl+B then D, reattach with: tmux attach -t jarvis)
#
# The server exits on its own after a long network outage, so this loop
# starts it again. Stop it with Ctrl+C twice.

cd "$(dirname "$0")/.." || exit 1

while true; do
  bash scripts/sync.sh --pull
  claude remote-control --name "Jarvis"
  echo "Remote Control stopped at $(date). Restarting in 30 seconds. Press Ctrl+C to quit."
  sleep 30 || exit 0
done
