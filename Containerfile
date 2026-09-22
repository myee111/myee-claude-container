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
      util-linux openssh-clients claude-code \
    && dnf --installroot $ROOTFS clean all

# Non-root user, OpenShift-style arbitrary-UID-friendly (group 0).
RUN useradd -R $ROOTFS -u 1001 -g 0 -M -d /home/claude -s /bin/bash claude \
    && mkdir -p $ROOTFS/home/claude/workspace $ROOTFS/home/claude/.config/gcloud \
             $ROOTFS/home/claude/.ssh $ROOTFS/home/claude/.claude \
    && chmod 700 $ROOTFS/home/claude/.ssh \
    && chown -R 1001:0 $ROOTFS/home/claude

# Auto-trust new SSH hosts (this is a non-interactive agent environment —
# an interactive host-key prompt would just hang) while still correctly
# failing on a *changed* host key.
RUN mkdir -p $ROOTFS/etc/ssh/ssh_config.d \
    && printf 'Host *\n    StrictHostKeyChecking accept-new\n' > $ROOTFS/etc/ssh/ssh_config.d/99-container.conf

# ---- Final: UBI 10 Micro ----
FROM registry.redhat.io/ubi10/ubi-micro

COPY --from=builder /mnt/rootfs/ /
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY claude-memory.md /home/claude/.claude/CLAUDE.md
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown 1001:0 /home/claude/.claude/CLAUDE.md

# Only a generic HOME path — no project ID, region, or credential path here.
ENV HOME=/home/claude

WORKDIR /home/claude/workspace

# No fixed USER here (defaults to root/0): the entrypoint needs root
# briefly to fix up the bind-mounted workspace's ownership (host-mounted
# dirs almost never already belong to uid 1001) and configure git's
# safe.directory, then it permanently drops privileges to uid 1001 before
# ever running your actual command. See entrypoint.sh.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
