#!/usr/bin/env bash
# install_pipeline_toolchain.sh -- put the analysis packages the PseudoCoup
# research line imports into THIS image, so its work can run as lanes instead
# of on the host.
#
# WHY THIS EXISTS
#   Ruled 2026-09-04: every computation runs through Airlock. The line's
#   modules (reference / ledger / canonical_form / gate / term / pool, and the
#   compiler graph) import pyvex, archinfo, z3, capstone, pyelftools and
#   tree-sitter. The image did not carry them, so the work kept running on the
#   host -- inside the desktop app's own cgroup, where a memory spike gets the
#   whole cgroup stopped by systemd-oomd and takes the app with it.
#
# WHAT IT DOES, and it is idempotent
#   1. writes requirements-analysis.txt (pinned)
#   2. adds ONE RUN line to the Containerfile that installs it, right after
#      the existing /opt/venv creation -- if the line is not already there
#   3. rebuilds the image with this repo's own build.sh
#   4. verifies by importing every package inside the built image
#
# WHAT IT DOES NOT DO
#   It does not restart a running instance. A rebuilt image is picked up the
#   next time an instance is brought up, so the default `sandbox` keeps
#   running on the image it started with until you take it down and up again.
#
# RUN IT WHEN YOU LIKE:
#   bash ~/Programming/Airlock/install_pipeline_toolchain.sh
set -euo pipefail
cd "$(dirname "$0")"

REQ=requirements-analysis.txt
MARKER='requirements-analysis.txt'

# ---- 1. the pinned list ---------------------------------------------------
# Versions are the ones the line's artifacts were built with, as recorded in
# DevComms logs 159-190 (pyvex 9.3.4, z3 5.1.0, capstone 5.0.7, tree-sitter
# 0.25.2, tree-sitter-cpp 0.23.4). archinfo and pyelftools were not pinned in
# a log, so they float; pin them here once a lane has reported its versions.
cat > "$REQ" <<'EOF'
pyvex==9.3.4
archinfo
capstone==5.0.7
pyelftools
z3-solver==5.1.0
tree-sitter==0.25.2
tree-sitter-c
tree-sitter-cpp==0.23.4
tree-sitter-go
tree-sitter-rust
EOF
echo "[1/4] wrote $REQ"

# ---- 2. one line in the Containerfile, only if absent ---------------------
if grep -q "$MARKER" Containerfile; then
    echo "[2/4] Containerfile already installs $REQ -- unchanged"
else
    python3 - <<'PY'
from pathlib import Path
p = Path("Containerfile")
text = p.read_text()
anchor = '    && chmod -R a+rwX /opt/venv\n'
if anchor not in text:
    raise SystemExit("Containerfile's /opt/venv block was not found -- "
                     "add the install line by hand and re-run")
block = anchor + '''
# ---- analysis packages the research lines import -------------------------
# Kept in requirements-analysis.txt so the pins are readable and one file to
# edit. See install_pipeline_toolchain.sh for why they are in the image.
COPY requirements-analysis.txt /opt/requirements-analysis.txt
RUN /opt/venv/bin/pip install --no-cache-dir -r /opt/requirements-analysis.txt \\
    && chmod -R a+rwX /opt/venv
'''
p.write_text(text.replace(anchor, block, 1))
print("    Containerfile: install line added after the /opt/venv block")
PY
    echo "[2/4] Containerfile updated"
fi

# ---- 3. rebuild -----------------------------------------------------------
echo "[3/4] rebuilding the image (this is the slow part) ..."
bash ./build.sh

# ---- 4. verify inside the built image -------------------------------------
echo "[4/4] verifying the imports inside the image ..."
IMAGE="$(podman images --format '{{.Repository}}:{{.Tag}}' | grep -i -m1 'sandbox\|airlock' || true)"
if [ -z "$IMAGE" ]; then
    echo "    could not name the built image; check 'podman images' and run:"
    echo "    podman run --rm <image> python3 -c \"import pyvex, archinfo, z3, capstone, elftools, tree_sitter; print('ok')\""
    exit 0
fi
podman run --rm "$IMAGE" python3 - <<'PY'
import importlib.metadata as m
for name, mod in [("pyvex","pyvex"), ("archinfo","archinfo"), ("z3-solver","z3"),
                  ("capstone","capstone"), ("pyelftools","elftools"),
                  ("tree-sitter","tree_sitter")]:
    __import__(mod)
    try:
        print("%-14s %s" % (name, m.version(name)))
    except Exception:
        print("%-14s imported (version not reported)" % name)
print("all imports ok")
PY
echo "done. A running instance keeps its old image until you take it down and up again."
