SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

# NOTE: .env is intentionally NOT pulled in via Make's own `-include`.
# GNU Make's parser treats `#` as a comment start ANYWHERE on a line
# (unlike bash), which silently truncates secrets containing `#`. Instead,
# each recipe below sources .env through bash itself, which respects the
# single-quoting used in .env/.env.example.

# Read IMAGE_NAME/IMAGE_TAG from .env via a bash subshell (not Make's own
# -include, for the same # /comment-parsing reason as above), falling back
# to a generic placeholder if .env is missing or doesn't set them. This
# means the real image reference lives only in .env, never hardcoded here.
IMAGE_NAME := $(shell if [ -f ./.env ]; then set -a; . ./.env; set +a; fi; echo "$${IMAGE_NAME:-quay.io/your-namespace/claude-container}")
IMAGE_TAG  := $(shell if [ -f ./.env ]; then set -a; . ./.env; set +a; fi; echo "$${IMAGE_TAG:-latest}")
LOCAL_IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: login-redhat login-quay build run push pull all check-env

check-env:
	if [ ! -f .env ]; then \
		echo "Missing .env. Copy .env.example to .env and fill in credentials first." >&2; \
		exit 1; \
	fi

login-redhat: check-env
	set -a; . ./.env; set +a
	echo "$$REDHAT_REGISTRY_PASSWORD" | podman login registry.redhat.io -u "$$REDHAT_REGISTRY_USERNAME" --password-stdin

login-quay: check-env
	set -a; . ./.env; set +a
	echo "$$QUAY_PASSWORD" | podman login quay.io -u "$$QUAY_USERNAME" --password-stdin

build: login-redhat
	podman build -t $(LOCAL_IMAGE) -f Containerfile .

run: check-env
	set -a; . ./.env; set +a
	mkdir -p workspace
	adc_path="$${ADC_HOST_PATH:-$$HOME/.config/gcloud/application_default_credentials.json}"
	tmp_dir="$$(mktemp -d)"
	trap 'rm -rf "$$tmp_dir"' EXIT
	install -m 644 "$$adc_path" "$$tmp_dir/adc.json"
	podman run --rm -it \
	  -v "$$tmp_dir/adc.json:/home/claude/.config/gcloud/application_default_credentials.json:ro,Z" \
	  -e CLAUDE_CODE_USE_VERTEX=1 \
	  -e CLOUD_ML_REGION="$${GCP_REGION:-global}" \
	  -e ANTHROPIC_VERTEX_PROJECT_ID="$$GCP_PROJECT_ID" \
	  -e GOOGLE_APPLICATION_CREDENTIALS=/home/claude/.config/gcloud/application_default_credentials.json \
	  -v "$(CURDIR)/workspace:/home/claude/workspace:Z" \
	  $(LOCAL_IMAGE)

push: login-quay
	podman push $(LOCAL_IMAGE)

# Convenience for a fresh host that just wants to pull the published image
# without building anything (still needs `make login-quay` first if the
# repo is private).
pull: login-quay
	podman pull $(LOCAL_IMAGE)

all: build push
