# claude-container client

Everything in this folder is all you need to run `claude` (backed by
`quay.io/myee/claude-container`) on any **x86_64 podman host**. No repo
clone, no build — just this folder.

## Setup (once per host)

1. Copy this whole `client/` folder to the host (scp, git, tarball, whatever).
2. Make sure `podman` is installed and Google ADC is set up:
   ```bash
   gcloud auth application-default login
   ```
3. Fill in credentials:
   ```bash
   cp .env.example .env
   $EDITOR .env   # remember: single-quote every value
   ```
4. Log podman into quay.io (the image is private):
   ```bash
   ./bin/login-quay
   ```
5. Put `bin/claude` on your `PATH` (or just call it by path):
   ```bash
   ln -s "$PWD/bin/claude" ~/.local/bin/claude
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
