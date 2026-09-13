#!/usr/bin/env bash
# devbox: build the image from Airlock's sandbox-runner.
set -euo pipefail
cd "$(dirname "$0")"
podman image exists localhost/sandbox-runner:latest || {
    echo "localhost/sandbox-runner:latest is not built here; run Airlock's build.sh first"; exit 1; }
podman build -t localhost/devbox:latest -f Containerfile .
echo "built localhost/devbox:latest"
echo "next: bash run.sh"
