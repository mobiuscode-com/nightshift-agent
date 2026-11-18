# syntax=docker/dockerfile:1.7
#
# The Nightshift agent image, the default project image (`nightshift.runner.default-image`): the build environment a
# run works in when its project names no image of its own. JDK 25, Node.js, Go, git, the usual build tools, the
# libraries a headless Chromium needs, and Docker Engine for runs on a sysbox runner (the runner starts dockerd in the
# container). The harness is not in here: the runner mounts it (github.com/mobiuscode-com/nightshift-harness). A project
# image of your own only has to meet the contract in this repository's README.
#
# Built from the repository root: docker build -t nightshift-agent .

ARG TEMURIN_IMAGE=eclipse-temurin:25.0.4.1_1-jdk-noble

FROM ${TEMURIN_IMAGE} AS fetch
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils gnupg \
 && rm -rf /var/lib/apt/lists/*
# `sha512 <base64 digest> <file>`: npm publishes its integrity as base64, sha512sum wants hex.
RUN printf '%s\n' '#!/bin/sh' 'set -eu' \
      'echo "$(printf %s "$1" | base64 -d | od -An -v -tx1 | tr -d " \n")  $2" | sha512sum -c -' \
      > /usr/local/bin/sha512-b64 \
 && chmod +x /usr/local/bin/sha512-b64

# Node.js for the agents (npm and npx are part of it). Moving it changes this ARG and both checksums together.
# Checksums from https://nodejs.org/dist/v<version>/SHASUMS256.txt.
FROM fetch AS node
ARG TARGETARCH
ARG NODE_VERSION=24.13.0
ARG NODE_SHA256_AMD64=e798599612f4bb71333a3397ab0d095fd62214e115aea45aa858a145fc72d67e
ARG NODE_SHA256_ARM64=aa881151bd0f9f154a0424dd60a72e9ce10672619121658c278a24327ef46831
RUN set -eu; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64) arch=x64;   sum="$NODE_SHA256_AMD64" ;; \
      arm64) arch=arm64; sum="$NODE_SHA256_ARM64" ;; \
      *) echo "unsupported architecture $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$arch.tar.xz"; \
    echo "$sum  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir /node; \
    tar -xJf /tmp/node.tar.xz -C /node --strip-components=1 --no-same-owner

# Go for the agents. Checksums from https://go.dev/dl/?mode=json.
FROM fetch AS go
ARG TARGETARCH
ARG GO_VERSION=1.27.2
ARG GO_SHA256_AMD64=ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5
ARG GO_SHA256_ARM64=94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8
RUN set -eu; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64) sum="$GO_SHA256_AMD64" ;; \
      arm64) sum="$GO_SHA256_ARM64" ;; \
      *) echo "unsupported architecture $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/go.tar.gz "https://go.dev/dl/go$GO_VERSION.linux-$arch.tar.gz"; \
    echo "$sum  /tmp/go.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/go.tar.gz -C / --no-same-owner

# Docker's apt signing key, checked against its published fingerprint.
FROM fetch AS docker-key
ARG DOCKER_KEY_FINGERPRINT=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
RUN set -eu; \
    curl -fsSL -o /docker.asc https://download.docker.com/linux/ubuntu/gpg; \
    gpg --show-keys --with-colons /docker.asc | grep -q "^fpr:::::::::$DOCKER_KEY_FINGERPRINT:"

# --- Runtime ----------------------------------------------------------------------------------------------------------
FROM ${TEMURIN_IMAGE}
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="Nightshift agent" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/mobiuscode-com/nightshift-agent"
ARG DOCKER_VERSION=5:29.9.1-1~ubuntu.24.04~noble
ARG CONTAINERD_VERSION=2.4.2-2~ubuntu.24.04~noble
ARG BUILDX_VERSION=0.38.0-1~ubuntu.24.04~noble
ARG COMPOSE_VERSION=5.6.0-1~ubuntu.24.04~noble

COPY --from=docker-key /docker.asc /etc/apt/keyrings/docker.asc
# build-essential and python3: native npm modules, cgo. The lib* packages are the shared libraries Chromium needs (the
# agents fetch it themselves, e.g. with `npx playwright install chromium`); the fonts give its screenshots
# metric-compatible Arial/Times/Courier and emoji.
RUN set -eu; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
      > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client ripgrep jq unzip zip xz-utils less procps \
      build-essential python3 \
      libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 \
      libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 \
      libxext6 libxfixes3 libxkbcommon0 libxrandr2 fonts-liberation fonts-noto-color-emoji \
      "docker-ce=$DOCKER_VERSION" "docker-ce-cli=$DOCKER_VERSION" "containerd.io=$CONTAINERD_VERSION" \
      "docker-buildx-plugin=$BUILDX_VERSION" "docker-compose-plugin=$COMPOSE_VERSION"; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --uid 10001 --create-home --shell /bin/bash --groups docker agent

COPY --from=node /node /opt/node
COPY --from=go /go /usr/local/go

ENV PATH=/home/agent/.npm-global/bin:/home/agent/go/bin:/opt/node/bin:/usr/local/go/bin:$PATH \
    GOPATH=/home/agent/go \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global

# The runner replaces the entrypoint and runs the agent as this user; it starts dockerd as root on a sysbox runner.
USER agent
WORKDIR /workspace
