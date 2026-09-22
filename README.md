# myee-claude-container

Claude Code running in a minimal UBI 10 Micro container, authenticated to
Anthropic through Google Vertex AI. Runs with `podman`. **x86_64 only.**

Image: `quay.io/myee/claude-container:latest`

---

## 1. Build

Only needed once (or whenever the `Containerfile` changes). Requires a copy
of this whole project directory (this is not currently a git repo with a
remote — copy it over with `scp`/`tar`/etc.), on an x86_64 host with `podman`
+ `make`.

```bash
cp .env.example .env
$EDITOR .env   # fill in REDHAT_REGISTRY_*, QUAY_*, GCP_PROJECT_ID (single-quote every value)

make all       # builds the image and pushes it to quay.io/myee/claude-container
```

That's it. `make all` = `make build` (pulls UBI base images from
`registry.redhat.io`, builds the image) + `make push` (publishes to quay.io).

---

## 2. Normal use

You do **not** need this repo for this part — just the
**[`client/`](client/)** folder. Copy it to any x86_64 podman host.

**One-time setup on that host:**

```bash
gcloud auth application-default login      # if not already done

cd client
cp .env.example .env
$EDITOR .env                                # fill in QUAY_USERNAME/PASSWORD, GCP_PROJECT_ID
./bin/login-quay                            # log podman into quay.io (image is private)

ln -s "$PWD/bin/claude" ~/.local/bin/claude # put `claude` on your PATH
```

**Every day after that:**

```bash
cd ~/any/project
claude                        # interactive REPL
claude -p "explain this repo" # one-shot, non-interactive
```

`claude` mounts whatever directory you're standing in, pulls the image from
quay.io automatically the first time, and uses your Google ADC credentials —
nothing needs to be rebuilt or re-cloned per project or per host.

See [`client/README.md`](client/README.md) for more detail on this half.
