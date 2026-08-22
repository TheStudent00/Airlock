# Airlock runner image.
#
# A broad, general-purpose toolchain, baked in so no run ever needs the
# network for its own setup. Haxe and Flutter were deliberately deferred
# (2026-07-30) and are not here. Nothing in this file is specific to any
# project; a project that needs another toolchain adds it here, which is
# a build-image change, not a per-run one.
#
# Everything is installed HERE, at build time, while the network is open.
# At run time the container sits on an --internal podman network and can
# reach nothing except the allowlist proxy. See up.sh.

FROM docker.io/library/ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ---- base OS + build tooling --------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git unzip xz-utils \
        build-essential gcc-15 g++-15 clang-21 lld-21 llvm-21 \
        make cmake ninja-build pkg-config \
        python3 python3-dev python3-pip python3-venv \
        golang-1.26 \
        nodejs npm \
        openjdk-25-jdk-headless \
        ruby perl php-cli \
        jq ripgrep fd-find plocate inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu ships Go under a versioned path; put it on PATH.
ENV PATH="/usr/lib/go-1.26/bin:${PATH}"

# Ubuntu installs clang/lld/llvm ONLY under version-suffixed names
# (/usr/bin/clang-21). Nothing creates the unsuffixed name, so scripts
# calling `clang` fail even though clang is installed. Same story for
# fd, which Debian renamed to `fdfind` to avoid a package collision.
RUN ln -sf /usr/bin/clang-21     /usr/bin/clang   && \
    ln -sf /usr/bin/clang++-21   /usr/bin/clang++ && \
    ln -sf /usr/bin/lld-21       /usr/bin/lld     && \
    ln -sf /usr/bin/llvm-config-21 /usr/bin/llvm-config && \
    ln -sf /usr/bin/fdfind       /usr/bin/fd

# ---- Python 3.13 to match the host ---------------------------------------
# Ubuntu 26.04 ships 3.14; the host develops on 3.13 (via Anaconda), and
# 3.13 is a very common development version. uv fetches a standalone
# 3.13 build, so this does not depend on Ubuntu packaging one.
# UV_PYTHON_BIN_DIR is the one that matters: without it uv puts the
# python3.13 symlink in /root/.local/bin, which is not on PATH.
ENV UV_INSTALL_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && uv python install 3.13 \
    && ln -sf "$(uv python find 3.13)" /usr/local/bin/python3.13 \
    && chmod -R a+rX /opt/python \
    && python3.13 --version
# A writable virtual environment built on the 3.13 interpreter, placed
# FIRST on PATH. Without this, `pip install` fails: both Ubuntu's 3.14 and
# uv's 3.13 are marked externally-managed under PEP 668, so pip refuses to
# touch them. With it, `python`, `python3`, and `pip` all mean 3.13 and
# behave the way they do on a normal dev machine.
#
# Ubuntu's own tooling hardcodes /usr/bin/python3, so it is unaffected.
RUN python3.13 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel \
    && chmod -R a+rwX /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV VIRTUAL_ENV=/opt/venv

# npm and nodejs are versioned independently in Ubuntu and drift apart
# (this image pairs node 22.22.1 with npm 9). npm@latest now requires
# node >=22.22.2, one patch newer than the distro ships, so pin to the
# newest line that accepts it — and never let this stop the build, since
# Node is incidental here.
RUN npm install -g npm@11 || echo "npm upgrade skipped (node too old for npm@11)"

# ---- Rust (not packaged at the host's version) --------------------------
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
ENV PATH="/opt/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain 1.96.1 \
    && chmod -R a+rX,a+w /opt/cargo /opt/rustup

# ---- runtime layout -----------------------------------------------------
# /drop   scripts land here; the daemon watches it
# /logs   one log file per run
# /work   scratch space, and where copied-in projects land
# /out    anything a script writes here is meant to come back to the host
RUN mkdir -p /drop /logs /work /out /opt/daemon
COPY daemon/watcher.py /opt/daemon/watcher.py

# Proxy variables are baked in so every script inherits them. The proxy
# hostname resolves only on the internal podman network.
ENV http_proxy=http://sandbox-proxy:3128 \
    https_proxy=http://sandbox-proxy:3128 \
    HTTP_PROXY=http://sandbox-proxy:3128 \
    HTTPS_PROXY=http://sandbox-proxy:3128 \
    no_proxy=localhost,127.0.0.1

WORKDIR /work
CMD ["python3", "-u", "/opt/daemon/watcher.py"]
