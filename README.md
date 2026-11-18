# Nightshift agent

The default image a [Nightshift](https://github.com/mobiuscode-com) run works in: a build environment for the coding
agent, used whenever a project names no image of its own.

```sh
docker pull ghcr.io/mobiuscode-com/nightshift-agent:<version>
```

| | |
|---|---|
| Base | Ubuntu 24.04 with Eclipse Temurin **JDK 25** |
| Languages | **Node.js** (npm, npx; global installs go to `~/.npm-global`), **Go** (`GOPATH=~/go`), Python 3 |
| Tools | git, openssh-client, ripgrep, jq, curl, zip/unzip, xz, build-essential (native npm modules, cgo) |
| Browsers | the shared libraries and fonts a headless Chromium needs; Chromium itself is **not** included — agents fetch it when they need it (e.g. `npx playwright install chromium`) |
| Docker | **Docker Engine** with containerd, the buildx and compose plugins. Only used on a **sysbox** runner, where the runner starts `dockerd` in the container so Testcontainers and `docker compose` work in a run |
| User | `agent` (uid 10001, in group `docker`), working directory `/workspace` |

The coding harness is not in here: the runner mounts
[nightshift-harness](https://github.com/mobiuscode-com/nightshift-harness) into the container at run time.

## Your own project image

A project can name any image in its settings in Nightshift. The runner replaces the image's entrypoint and runs the
agent as the image's `USER`. The image has to offer:

- linux/amd64 or linux/arm64
- **glibc** (the harness's Node build is glibc-only; Alpine images do not work)
- a POSIX `sh`, `git`, `tar` and CA certificates

The runner checks every requirement before a run starts and ends the run with a message naming what is missing.

The easy way is to extend this image:

```dockerfile
FROM ghcr.io/mobiuscode-com/nightshift-agent:<version>
USER root
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client && rm -rf /var/lib/apt/lists/*
USER agent
```

## Versions

Releases follow [Semantic Versioning](https://semver.org) and are made automatically from the commit messages
([Conventional Commits](https://www.conventionalcommits.org): `feat:` a minor release, `fix:`/`perf:` a patch, a
breaking change a major; `chore`, `docs`, `refactor`, `style` and `test` release nothing). Every release is pushed as
`<version>`, `<major>.<minor>`, `<major>` and `latest`, for linux/amd64 and linux/arm64. Removing a tool or changing
the user is a breaking change.

Pin an exact version. Docker only pulls an image it does not have, so a moving tag like `latest` stays whatever a
machine pulled first.

## Building

```sh
docker build -t nightshift-agent:dev .
```

Every download is pinned by version **and** checksum, the apt packages of Docker by version; change both together.
