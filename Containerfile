# syntax=docker/dockerfile:1
#
# Minimal Claude Code dev container on UBI 10 Micro.
#
# This image contains NO project-specific information: no GCP project ID,
# no region, no credential paths, no secrets. All Vertex AI configuration
# (CLAUDE_CODE_USE_VERTEX, CLOUD_ML_REGION, ANTHROPIC_VERTEX_PROJECT_ID,
# GOOGLE_APPLICATION_CREDENTIALS) is supplied at `podman run` time so the
# same image can be pulled and reused by anyone with their own GCP project
# and credentials.

# ---- Builder: assemble a minimal rootfs with dnf --installroot ----
FROM registry.redhat.io/ubi10/ubi AS builder

# Anthropic's signed dnf repo for the Claude Code native binary (RPM package).
RUN tee /etc/yum.repos.d/claude-code.repo <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
EOF

ENV ROOTFS=/mnt/rootfs
RUN mkdir -p $ROOTFS

# Install only what's needed for an interactive Claude Code dev shell into
# the rootfs. dnf resolves and pulls in any transitive runtime deps
# (e.g. libstdc++/libgcc) automatically.
RUN dnf install -y \
      --installroot $ROOTFS \
      --releasever=/ \
      --setopt=reposdir=/etc/yum.repos.d/ \
      --setopt=install_weak_deps=false \
      --nodocs \
      bash coreutils git ca-certificates tar gzip curl-minimal \
      findutils grep sed gawk diffutils which glibc-langpack-en \
      claude-code \
    && dnf --installroot $ROOTFS clean all

# Non-root user, OpenShift-style arbitrary-UID-friendly (group 0).
RUN useradd -R $ROOTFS -u 1001 -g 0 -M -d /home/claude -s /bin/bash claude \
    && mkdir -p $ROOTFS/home/claude/workspace $ROOTFS/home/claude/.config/gcloud \
    && chown -R 1001:0 $ROOTFS/home/claude

# ---- Final: UBI 10 Micro ----
FROM registry.redhat.io/ubi10/ubi-micro

COPY --from=builder /mnt/rootfs/ /

# Only a generic HOME path — no project ID, region, or credential path here.
ENV HOME=/home/claude

WORKDIR /home/claude/workspace
USER 1001

CMD ["/bin/bash"]
