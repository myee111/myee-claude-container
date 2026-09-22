# myee-claude-container

Claude Code running in a minimal UBI 10 Micro container, authenticated to
Anthropic through Google Vertex AI. Runs with `podman`. **x86_64 only.**

Image: `quay.io/myee/claude-container:latest`
Repo: `https://github.com/myee111/myee-claude-container` (private)

---

## 1. Build — **requires the git repo**

Only needed once (or whenever the `Containerfile` changes), on an x86_64
host with `podman`, `make`, and `git`.

```bash
git clone https://github.com/myee111/myee-claude-container.git
cd myee-claude-container

cp .env.example .env
$EDITOR .env   # fill in REDHAT_REGISTRY_*, QUAY_*, GCP_PROJECT_ID (single-quote every value)

make all       # builds the image and pushes it to quay.io/myee/claude-container
```

That's it. `make all` = `make build` (pulls UBI base images from
`registry.redhat.io`, builds the image) + `make push` (publishes to quay.io).

You need the git repo here because `make build` uses the `Containerfile` and
`Makefile` that live in it.

---

## 2. Normal use — **does NOT require the git repo**

This is the everyday path: running the already-built, already-published
image. You do not need to `git clone` anything for this — you only need the
**[`client/`](client/)** folder, which is fully self-contained. Get it onto
the target host any way you like: `git clone` + copy just that folder,
`scp`/`rsync` it directly, download it as a tarball, etc.

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

---

## Summary: do I need the git repo?

| Task | Needs git repo? |
| --- | --- |
| Build a new image version (`make build`/`make all`) | **Yes** |
| Run `claude` day-to-day on any host | **No** — just the `client/` folder |
| Change the `Containerfile`/`Makefile` | **Yes** |
| Push to quay.io (`make push`) | **Yes** (it's a `make` target in the repo) |
| Point `claude` at a different GCP project/region | **No** — edit `client/.env` or set env vars inline |
