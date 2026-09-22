# claude-container client

Everything in this folder is all you need to run `claude` (backed by
`quay.io/myee/claude-container`) on any **x86_64 podman host**.

The [myee-claude-container](https://github.com/myee111/myee-claude-container)
repo itself is only needed to *build* a new image version — you don't need
to work inside a full checkout of it just to run `claude`. Cloning it once
to grab this folder is still the easiest way to *get* it onto a new host
(see below) — the repo is a handful of small text files, so pulling the
whole thing costs nothing. **The repo is public, so no GitHub auth/token is
needed to clone it** (`quay.io` credentials in step 4 are a separate thing —
the container *image* is still private).

## Setup (once per host)

1. Get this folder onto the host — **one command, no auth needed**:

   ```bash
   git clone --depth 1 https://github.com/myee111/myee-claude-container.git && cd myee-claude-container/client
   ```

   (Already have the `gh` CLI? `gh repo clone myee111/myee-claude-container -- --depth 1` works the same way.)

2. Make sure `podman` is installed.
3. Get a Google Application Default Credentials (ADC) JSON file onto this
   host. **The `gcloud` CLI is not required on this host** — the container
   only needs the resulting file, not the CLI itself. Pick whichever option
   is easiest:

   - **Option A — copy a file that already exists.** If you (or anyone else)
     already ran `gcloud auth application-default login` somewhere, just
     copy `~/.config/gcloud/application_default_credentials.json` from that
     machine to this host with `scp`/`rsync`/etc. Nothing to install here.
   - **Option B — service account key (no `gcloud` involved anywhere).**
     In the GCP Console web UI: create a service account, grant it
     `roles/aiplatform.user`, create a JSON key, download it, and copy that
     file to this host. Point `ADC_HOST_PATH` at it in `.env` (see step 4).
   - **Option C — GCE metadata server.** If this host is itself a GCE VM
     with an attached service account that has `roles/aiplatform.user`, no
     file is needed at all — but `bin/claude` currently always mounts a
     file, so use Option A or B for now even on a GCE VM.
   - **Option D — install `gcloud` on this host and log in interactively**
     (see below), if you'd rather do it directly on the host.

4. Fill in credentials:
   ```bash
   cp .env.example .env
   $EDITOR .env   # remember: single-quote every value; set ADC_HOST_PATH
                  # if your credentials file isn't at the default gcloud location
   ```
5. Log podman into quay.io (the image is private):
   ```bash
   ./bin/login-quay
   ```
6. Put `bin/claude` on your `PATH` (or just call it by path):
   ```bash
   ln -s "$PWD/bin/claude" ~/.local/bin/claude
   ```

### Option D: installing the `gcloud` CLI on this host

Only needed if you want to run `gcloud auth application-default login`
directly on this host instead of using Option A or B above.

**RHEL 10 / any Linux / macOS — installer script (recommended, no root needed):**
```bash
curl -sSL https://sdk.cloud.google.com | bash
exec -l "$SHELL"   # reload your shell so `gcloud` is on PATH
gcloud auth application-default login
```

> **RHEL 10 note:** the `dnf`-based install below currently **fails on RHEL
> 10** with `Policy rejects ...: No binding signature` — RHEL 10's stricter
> `rpm-sequoia` GPG backend rejects Google's current repo signing key. This
> is a real, reproducible issue on RHEL 10 (confirmed independently of any
> particular host), not a local misconfiguration. Use the installer script
> above instead. It's also just easier — no root/repo setup required.

**RHEL 9 / Fedora / CentOS (`dnf`, works fine there):**
```bash
sudo tee /etc/yum.repos.d/google-cloud-sdk.repo <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo dnf install -y google-cloud-cli
gcloud auth application-default login
```

**Debian / Ubuntu (`apt`):**
```bash
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli
gcloud auth application-default login
```

**macOS (Homebrew):**
```bash
brew install --cask google-cloud-sdk
gcloud auth application-default login
```

## Use it

```bash
cd ~/any/project
claude                        # interactive REPL
claude -p "explain this repo" # one-shot, non-interactive
```

The first run pulls the image automatically; after that it's cached locally.
`claude` mounts whatever directory you're standing in, so it works the same
way across every project on this host.

## Notes

- This image is `linux/amd64` (x86_64) only.
- Your Google ADC file's real permissions on disk are never changed — the
  wrapper copies it to a private temp location per-run to work around
  rootless podman's UID remapping, then deletes the copy.
- To point at a different GCP project/region without editing `.env`:
  ```bash
  GCP_PROJECT_ID='other-project' GCP_REGION='us-east5' claude
  ```
