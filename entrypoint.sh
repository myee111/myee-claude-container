#!/bin/bash
# Runs as root at container start (see Containerfile: no fixed USER anymore).
# Bind-mounted workspaces are owned by whatever UID created them on the
# HOST, which essentially never matches this image's fixed non-root
# CLAUDE_UID/GID (1001:0) — so without this, git refuses to operate
# ("dubious ownership") and file edits fail as read-only. Fix ownership
# and git's safe-directory check here, once, while we still have root,
# then permanently drop to the unprivileged user for the actual workload.
set -e

CLAUDE_UID=1001
CLAUDE_GID=0
WORKSPACE=/home/claude/workspace

if [ "$(id -u)" = "0" ]; then
  if [ -d "$WORKSPACE" ]; then
    chown -R "$CLAUDE_UID:$CLAUDE_GID" "$WORKSPACE" 2>/dev/null || true
  fi
  # Belt-and-suspenders: trust the workspace regardless of ownership too,
  # in case chown can't fully succeed (e.g. some exotic mount types).
  git config --system --add safe.directory "$WORKSPACE" 2>/dev/null || true
  git config --system --add safe.directory '*' 2>/dev/null || true

  exec setpriv --reuid="$CLAUDE_UID" --regid="$CLAUDE_GID" --clear-groups -- "$@"
fi

exec "$@"
