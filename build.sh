#!/usr/bin/env bash
# Build both images. This is the ONLY phase with open network access:
# every toolchain gets baked in here so the runner never needs the
# internet for its own setup.
#
# Usage:  ./build.sh [--instance NAME]
#
# The image is a BUILD ARTIFACT shared by every instance: the default
# instance builds sandbox-runner:latest and a second instance reuses it.
# --instance matters only when an instance names a different image in its
# instances/<name>.conf (runner_image / proxy_image).
set -euo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"


echo "=== building $AL_RUNNER_IMAGE (this takes a while) ==="
podman build -t "$AL_RUNNER_IMAGE" -f Containerfile .

echo "=== building $AL_PROXY_IMAGE ==="
podman build -t "$AL_PROXY_IMAGE" -f proxy/Containerfile.proxy .

echo
echo "done. images:"
podman images --filter reference="${AL_RUNNER_IMAGE%%:*}" --filter reference="${AL_PROXY_IMAGE%%:*}" \
    --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'
echo
echo "next:  ./up.sh"
