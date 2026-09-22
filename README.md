# myee-claude-container

Claude Code running in a minimal UBI 10 Micro container, authenticated to
Anthropic through Google Vertex AI. Runs with `podman`. **x86_64 only.**

Image: `quay.io/myee/claude-container:latest` (private — needs quay.io auth to pull)
Repo: `https://github.com/myee111/myee-claude-container` (public — no auth needed to clone)

---

## 1. Build — **requires the git repo**

Only needed once (or whenever the `Containerfile` changes), on an x86_64
host with `podman`, `make`, and `git`. No GitHub auth needed — the repo is
public.

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

## 2. Normal use — **doesn't require *working out of* the git repo**

This is the everyday path: running the already-built, already-published
image. You never run `make`/touch the `Containerfile` for this — you only
need the **[`client/`](client/)** folder. The easiest way to get just that
folder onto a new host is still one `git clone` command, **no auth needed**
(the repo is public — only the container *image* on quay.io is private):

```bash
git clone --depth 1 https://github.com/myee111/myee-claude-container.git && cd myee-claude-container/client
```

**One-time setup on that host:**

```bash
gcloud auth application-default login      # if not already done

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
| Run `claude` day-to-day on any host | **No** — just the `client/` folder (though `git clone` is the easiest one-step way to fetch it) |
| Change the `Containerfile`/`Makefile` | **Yes** |
| Push to quay.io (`make push`) | **Yes** (it's a `make` target in the repo) |
| Point `claude` at a different GCP project/region | **No** — edit `client/.env` or set env vars inline |
