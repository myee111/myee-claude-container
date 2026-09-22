---
name: minimal-claude-container
description: >-
  Build, debug, and extend a minimal Claude Code container on UBI 10
  Micro/RHEL, run with podman, authenticated to Anthropic via Google Vertex
  AI, published to a private container registry (quay.io). Use when working
  on this myee-claude-container project, building similar podman/UBI-based
  Claude Code containers, setting up Vertex AI auth for Claude Code, or
  debugging podman rootless/rootful image-store mismatches, SELinux-labeled
  bind mounts, container UID/permission errors, unqualified image names, or
  ssh-agent forwarding into containers.
---

# Minimal Claude Code container on UBI/RHEL with Vertex AI + podman

Distilled lessons from building this repo: a UBI 10 Micro image with Claude
Code, authenticated via Google Vertex AI, built/run with podman, published
to quay.io. Every gotcha below was hit and fixed for real — treat the
actual files in this repo as the canonical reference, not just this
summary.

## The two-role split

- **Build** needs the full repo (`Containerfile`, `Makefile`, `entrypoint.sh`).
- **Run** only needs the tiny `client/` folder (`bin/claude`, `bin/setup.sh`,
  `bin/pull`, `bin/login-quay`, `.env.example`) — self-contained, no repo
  clone needed on run-only hosts. Keep this split for any similar project.

## Working Containerfile pattern

Multi-stage: builder (`ubi10/ubi`, has `dnf`) assembles a rootfs via
`dnf install --installroot`, then `COPY --from=builder` into `ubi10/ubi-micro`
(no package manager). See [Containerfile](../../../Containerfile).

- Install Claude Code via Anthropic's **signed dnf repo**
  (`https://downloads.claude.ai/claude-code/rpm/stable`) — it's a native
  binary, no Node.js needed at runtime.
- Never bake project-specific values (GCP project ID, region, credential
  paths) into the image. Inject at `podman run` time via env vars from
  `.env` instead — the same image works for anyone.
- No fixed `USER` in the final image. Use an entrypoint that starts as root,
  fixes bind-mount ownership/permissions, then drops privileges (see below).

## Entrypoint: fix bind-mount ownership, then drop privileges

Bind-mounted host directories/files essentially never already belong to the
image's non-root uid (e.g. 1001). Without a fix, `git` refuses to operate
("dubious ownership") and writes fail as read-only.

Pattern (see [entrypoint.sh](../../../entrypoint.sh)):
1. Container starts as root (no `USER` line in Containerfile).
2. Entrypoint `chown -R`s the mounted workspace + any imported `~/.ssh` to
   the target uid:gid, sets `git config --system --add safe.directory`.
3. `exec setpriv --reuid=<uid> --regid=<gid> --clear-groups -- "$@"` to
   permanently drop to the unprivileged user before running anything else.
4. Needs the `util-linux` package (provides `setpriv`) — not in `util-linux-core`.

## Host wrapper script pattern (bin/claude)

A bash wrapper on the host makes `claude` feel native: mounts `$PWD` as the
workspace, injects env vars from `.env`, handles credential-permission
mismatches. See [client/bin/claude](../../../client/bin/claude).

**Critical bug to avoid**: resolve symlinks before computing the script's
own directory. If setup docs tell users to `ln -s bin/claude ~/.local/bin/claude`
(and they should — that's how you make it feel like a real command), a
plain `dirname "${BASH_SOURCE[0]}"` resolves to the **symlink's** directory,
not the real one, and then fails to find `.env` sitting right next to the
real script. Use a portable resolve-symlinks loop (works on GNU+BSD):

```bash
resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [ -h "$source" ]; do
    local dir; dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}
```

## Credential-permission mismatch fix (ADC files, SSH keys)

Host credential files are normally mode `600`, owned by the host user. The
container's non-root uid can't read them directly (rootless podman remaps
container uids to a host subuid range; even rootful, uid 1001 ≠ real owner).

Fix: **copy, don't mount directly**. In the wrapper script, copy the file
into a private (`mktemp -d`, mode 700) temp dir with `install -m 644`, mount
*that* read-only, delete on exit (`trap ... EXIT`). Never modify the real
file's permissions on disk.

## IMAGE_NAME must be fully qualified

`podman run some-name:latest` (no registry host) makes podman silently
guess a registry from `/etc/containers/registries.conf`'s
`unqualified-search-registries` — it picked `registry.access.redhat.com`
in one real case instead of `quay.io`, failing with a confusing
`name unknown: Repo not found` that gives no hint the real issue is a
misconfigured `IMAGE_NAME`. Validate before ever calling podman:

```bash
registry_part="${IMAGE_NAME%%/*}"
if [[ "$IMAGE_NAME" != */* ]] || [[ "$registry_part" != *.* && "$registry_part" != *:* && "$registry_part" != "localhost" ]]; then
  echo "IMAGE_NAME must be fully qualified, e.g. quay.io/ns/repo" >&2; exit 1
fi
```

## .env quoting — Makefile vs bash

Never let **Make's own** `-include .env` parse a file containing secrets:
GNU Make treats `#` as a comment **anywhere on a line** (unlike bash),
silently truncating any password containing `#`. Source `.env` through
**bash** instead (`set -a; . ./.env; set +a`), and single-quote every value
in `.env` (`VAR='value'`) so `$`, `#`, `*` survive bash sourcing unmangled.

Also: `SHELL := /usr/bin/env bash` in a Makefile does **not** work — Make
execs `$(SHELL)` directly with no shell-word-splitting, so it looks for a
literal file named `/usr/bin/env bash`. Use `SHELL := /bin/bash`.

## registry.redhat.io vs quay.io are unrelated accounts

Pulling UBI base images needs `registry.redhat.io` creds. Pushing your
built image needs **separate** `quay.io` creds — same username/password
almost never works across both. Robot accounts on quay.io **cannot create
new repositories**; the repo must exist first with the robot explicitly
granted Write under *Repository Settings → User and Robot Permissions*.

## Rootless vs rootful podman: separate everything

`podman` as a normal user (rootless) and `sudo podman` (rootful) have
**completely separate image stores, auth files, and build caches**. Building
in one and testing in the other silently uses a stale image — a repeated
source of "my fix isn't working" confusion in this project. If reproducing
a bug that only happens for `root` users, build **and** test with `sudo
podman`, not a mix.

## SELinux + bind mounts

- Use `:Z` (private label) or `:z` (shared label) on bind mounts, or SELinux
  blocks access even for files with matching UID ownership — this is
  independent of and in addition to normal DAC permission bits.
- A freshly-created host file/socket (default type like `user_tmp_t`) is not
  container-accessible until relabeled; `:Z`/`:z` do this automatically.
- `getenforce` / temporarily `setenforce 0` / `--security-opt label=disable`
  (scoped to one container, not system-wide) are the right diagnostic tools
  — don't disable SELinux system-wide as a "fix".
- `ausearch -m avc` can show **no denials** even when SELinux is genuinely
  the blocker (some rules are `dontaudit`). Don't trust an empty audit log
  as proof SELinux isn't involved.

## ssh-agent forwarding into containers: unreliable, have a fallback

Bind-mounting `$SSH_AUTH_SOCK` and setting `SSH_AUTH_SOCK` in the container
looks correct and may pass the SELinux/DAC checks, but the ssh-agent
**protocol** itself can still fail ("communication with agent failed") for
reasons tied to host SELinux/kernel namespace policy that aren't
straightforward to fix. Treat it as a **best-effort bonus**, not the primary
mechanism. The reliable approach: copy `~/.ssh` into a temp dir with relaxed
(0644) permissions (same pattern as ADC above), mount read-only, have the
entrypoint copy it into the container's own `~/.ssh` and fix real
permissions (600 private keys, 644 public/known_hosts) there. Add
`StrictHostKeyChecking accept-new` via `/etc/ssh/ssh_config.d/*.conf` so
first-time connections don't hang waiting for an interactive prompt.

## RHEL 10 + Google Cloud CLI: dnf install fails

`dnf install google-cloud-cli` fails on RHEL 10 specifically with
`Policy rejects ...: No binding signature` — RHEL 10's stricter
`rpm-sequoia` GPG backend rejects Google's current repo signing key. This is
a real, reproducible RHEL10-specific issue, not a local misconfiguration.
Use the official installer script instead: `curl -sSL https://sdk.cloud.google.com | bash`.

## .containerignore footguns

A blanket `*.md` exclusion silently blocks any `.md` file you `COPY` into
the image (e.g. a `CLAUDE.md` memory file) from ever reaching the build
context — no error, the file is just silently absent. Use a negation line
(`!specific-file.md`) for anything you actually need copied in.

## Give Claude Code environment awareness

If Claude Code runs *inside* a container it built/is running in, it has no
idea unless told. Bake a `~/.claude/CLAUDE.md` (Claude Code's user-level
memory file, loaded every session) into the image describing: what
persists vs. is ephemeral, what tools exist (and notably what's
**missing** — e.g. no package manager/`sudo` at runtime in a minimal
image), and how any special mechanisms (like the SSH setup above) work. See
[claude-memory.md](../../../claude-memory.md) (copied to that path in the
Containerfile).

## Verify claims for real, every time

Nearly every fix in this project that was shipped on theory alone turned
out subtly broken on first real test (stale image caches, rootless/rootful
mismatches, a symlink bug that would have broken the officially documented
setup for every single user). Before declaring something fixed: reproduce
the original failure for real, apply the fix, re-verify the exact failing
scenario succeeds, then clean up test artifacts. Don't trust "this should
work" reasoning alone for anything involving containers, namespaces, or
SELinux.
