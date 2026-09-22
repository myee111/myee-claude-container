#!/usr/bin/env bash
# One-shot setup for this client/ bundle. Assumes:
#   - git and podman are already installed
#   - you've already copied a filled-in .env into this client/ directory
#     (cp .env.example .env && edit it, or scp/copy a pre-filled one in)
#   - ADC_HOST_PATH in .env (or the default gcloud location) already points
#     to a real Google Application Default Credentials file on this host
#
# Does the rest in one step: validates .env, logs podman into quay.io, and
# puts `claude` on your PATH.
set -euo pipefail

# See bin/claude for why this resolves symlinks instead of a plain dirname.
resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [ -h "$source" ]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"
CLIENT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$CLIENT_DIR"

if [[ ! -f .env ]]; then
  echo "setup.sh: Missing .env in $CLIENT_DIR." >&2
  echo "          Copy a filled-in .env here first (cp .env.example .env && edit it)." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a

: "${QUAY_USERNAME:?QUAY_USERNAME not set in .env}"
: "${QUAY_PASSWORD:?QUAY_PASSWORD not set in .env}"
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID not set in .env}"

IMAGE_NAME="${IMAGE_NAME:-quay.io/your-namespace/claude-container}"
registry_part="${IMAGE_NAME%%/*}"
if [[ "$IMAGE_NAME" != */* ]] || [[ "$registry_part" != *.* && "$registry_part" != *:* && "$registry_part" != "localhost" ]]; then
  echo "setup.sh: IMAGE_NAME='$IMAGE_NAME' in .env is not fully qualified." >&2
  echo "          Set it to something like 'quay.io/myee/claude-container'." >&2
  exit 1
fi

ADC_HOST_PATH="${ADC_HOST_PATH:-$HOME/.config/gcloud/application_default_credentials.json}"
if [[ ! -f "$ADC_HOST_PATH" ]]; then
  echo "setup.sh: warning — no ADC file found at $ADC_HOST_PATH yet." >&2
  echo "          'claude' will fail until one exists there (or ADC_HOST_PATH in .env points to one)." >&2
fi

echo "==> Logging podman into quay.io as $QUAY_USERNAME..."
echo "$QUAY_PASSWORD" | podman login quay.io -u "$QUAY_USERNAME" --password-stdin

echo "==> Linking bin/claude onto your PATH..."
mkdir -p "$HOME/.local/bin"
ln -sf "$CLIENT_DIR/bin/claude" "$HOME/.local/bin/claude"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  shell_rc="$HOME/.bashrc"
  [[ -n "${ZSH_VERSION:-}" ]] && shell_rc="$HOME/.zshrc"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
  echo "==> Added \$HOME/.local/bin to PATH in $shell_rc — run: source $shell_rc (or start a new shell)"
else
  echo "==> \$HOME/.local/bin is already on PATH."
fi

echo "==> Setup complete. Try: claude -p 'say hi'"
