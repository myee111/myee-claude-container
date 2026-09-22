# Container environment

You are running inside a minimal container (UBI 10 Micro base image, run
with `podman`), not directly on the user's host machine. Keep this in mind:

## Filesystem

- Only `/home/claude/workspace` is real, persistent storage — it's a bind
  mount of a directory on the host. Anything you write there is visible
  on the host immediately and survives after this container exits.
- Everything else in the container's filesystem (aside from a few other
  explicit mounts noted below) is ephemeral: it resets to the base image
  state on every new `podman run`. Don't rely on state outside
  `/home/claude/workspace` persisting between sessions.
- You do not have access to the host's filesystem outside of whatever
  directory was mounted as the workspace (typically the directory the user
  was standing in when they ran `claude`). You cannot see or read other
  files/projects on the host machine unless the user explicitly mounts them.

## Available tools

- A real `bash` shell, `git`, `ssh`/`scp` (OpenSSH client), `curl`,
  `coreutils`, `grep`/`sed`/`gawk`/`diffutils`/`findutils`/`tar`/`gzip`.
- There is **no package manager available at runtime** (no `dnf`/`yum`/
  `apt`, and no `sudo`) — this is a deliberately minimal image. If a task
  needs a tool that isn't installed, say so rather than trying to install
  it; the user would need to add it to the image build instead.
- No language runtimes beyond what's explicitly listed above are
  guaranteed to be present (e.g. don't assume Node.js, Python, etc. exist
  unless you've verified it in this specific environment).

## SSH access to other systems

- `ssh`/`scp` are installed. If the user's host has a `~/.ssh` directory,
  its contents are copied into this container's own `~/.ssh` at startup
  (with correct permissions fixed up) — so keys that work for the user on
  their host should work the same way for you in here.
- `SSH_AUTH_SOCK` (ssh-agent forwarding) may also be set as a bonus, but
  it's best-effort and depends on the host's SELinux/kernel namespace
  policy — it doesn't work on every host. If `ssh-add -l` reports a
  communication/permission error but key-based `ssh`/`scp` still works,
  that's expected; don't treat it as a real problem to fix.
- New hosts are auto-trusted on first connect (`StrictHostKeyChecking
  accept-new`), so you generally won't get an interactive host-key prompt
  for hosts you haven't connected to before. A *changed* host key will
  still correctly fail rather than being silently accepted.

## Networking

- You're on the container's normal network namespace (whatever the host's
  `podman run` configured — typically standard outbound access, no
  special restrictions beyond that).

## Vertex AI

- You (Claude Code itself) are authenticated to Anthropic via Google
  Vertex AI, not a direct Anthropic API key. This is unrelated to any
  Google Cloud work you might be asked to do in the workspace — it's just
  how this session is authenticated.
