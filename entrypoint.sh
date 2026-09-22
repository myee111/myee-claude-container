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

  # Forwarded ssh-agent socket (best-effort — works on some hosts, blocked
  # by SELinux/namespace policy on others; harmless to attempt either way
  # since ssh falls back to key files if the agent isn't reachable).
  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    chown "$CLAUDE_UID:$CLAUDE_GID" "$SSH_AUTH_SOCK" 2>/dev/null || true
  fi

  # Primary, reliable SSH mechanism: bin/claude stages a copy of the
  # host's ~/.ssh into a read-only mount at /home/claude/.ssh-import (with
  # relaxed perms so uid 1001 can read it — see bin/claude for why).
  # Copy it into the container's own writable ~/.ssh here, fix the perms
  # OpenSSH actually requires (600 on private keys, 644 on everything
  # else), and chown it all to the unprivileged user.
  if [ -d /home/claude/.ssh-import ]; then
    cp -a /home/claude/.ssh-import/. /home/claude/.ssh/ 2>/dev/null || true
    find /home/claude/.ssh -maxdepth 1 -type f \
      ! -name '*.pub' ! -name 'known_hosts*' ! -name 'config' ! -name 'authorized_keys' \
      -exec chmod 600 {} \; 2>/dev/null || true
    find /home/claude/.ssh -maxdepth 1 -type f \
      \( -name '*.pub' -o -name 'known_hosts*' -o -name 'config' \) \
      -exec chmod 644 {} \; 2>/dev/null || true
  fi
  if [ -e /home/claude/.ssh ]; then
    chown -R "$CLAUDE_UID:$CLAUDE_GID" /home/claude/.ssh 2>/dev/null || true
  fi

  exec setpriv --reuid="$CLAUDE_UID" --regid="$CLAUDE_GID" --clear-groups -- "$@"
fi

exec "$@"
