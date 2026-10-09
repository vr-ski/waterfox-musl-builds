# Waterfox musl builds

[![Build Waterfox musl](https://github.com/vr-ski/waterfox-musl-builds/actions/workflows/build.yml/badge.svg)](https://github.com/vr-ski/waterfox-musl-builds/actions/workflows/build.yml) [![Latest Release](https://img.shields.io/github/v/release/vr-ski/waterfox-musl-builds)](https://github.com/vr-ski/waterfox-musl-builds/releases) [![Last Commit](https://img.shields.io/github/last-commit/vr-ski/waterfox-musl-builds)](https://github.com/vr-ski/waterfox-musl-builds/commits/main) [![License: MPL 2.0](https://img.shields.io/badge/License-MPL%202.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0) [![License: BSD-2-Clause](https://img.shields.io/badge/License-BSD%202--Clause-blue.svg)](https://opensource.org/licenses/BSD-2-Clause)

Unofficial musl builds of [Waterfox](https://www.waterfox.com/), built in Alpine Linux containers and packaged as portable tarballs.
The official Waterfox project distributes glibc builds only. This project fills that gap for musl-based distributions.

## What you get

Four artefacts per Waterfox release:

| Artefact | Toolkit | CPU baseline | Runs on |
|---|---|---|---|
| `waterfox-musl-wayland-baseline-<ver>.tar.xz` | Wayland | x86-64-v2 | Nehalem and newer |
| `waterfox-musl-wayland-avx2-<ver>.tar.xz` | Wayland | x86-64-v3 | Haswell and newer |

Each tarball ships with a `.sha256` checksum. Each version is build with XWayland support, which means it should work on regular X11 as well. Both audio backends (ALSA and PulseAudio) are compiled into every binary; the runtime picks whichever is available.

## Installation

```bash
tar -xJf waterfox-musl-wayland-baseline-6.7.4.tar.xz -C /opt/
ln -sf /opt/waterfox/waterfox /usr/local/bin/waterfox
```

The binary links against `libc.musl-x86_64.so.1`. It will not run on glibc systems.

## Building locally

Prerequisites:

- `podman` or `docker`
- `git`, `curl`, `tar`, `patch` on the host
- 30 GB of RAM available to the container during the link step.
- 60 GB of free disk for source, object files, and the final artifact.

```bash
# Fetch the latest Waterfox release
scripts/fetch-upstream.sh ./waterfox-src

# Build the toolchain image
podman build -t waterfox-musl-builder:latest .

# Build one flavour
mkdir -p output
```bash
podman run --rm -it \
  -e FLAVOUR=wayland \
  -e CPU_TIER=avx2 \
  -e NSPR_VERSION="" \
  -e SCCACHE_DIR=/sccache \
  -e SCCACHE_BASEDIRS=/build \
  -v "$(pwd)/waterfox-src:/build/waterfox" \
  -v "$(pwd)/build:/build/obj" \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/sccache:/sccache" \
  waterfox-musl-builder:latest \
  sh /build/scripts/build.sh
```

To build a different flavour, change `FLAVOUR` and `CPU_TIER`. Valid values:

- `FLAVOUR`: `x11`, `wayland`
- `CPU_TIER`: `baseline`, `avx2`

`FLAVOUR` accepts `wayland` or `x11`. The Wayland build includes X11 fallback, so `wayland` is used in the release pipeline to covers both protocols, `x11` can be used manually for a pure x11 build.
`CPU_TIER` accepts `baseline` (x86-64-v2) or `avx2` (x86-64-v3).
Leave `NSPR_VERSION` empty to use the NSPR that ships with the source tree, or set it to a specific version (e.g. `4.39`) to pin.

The resulting tarball lands in `output/`:

```
output/waterfox-musl-wayland-avx2-6.7.5.tar.xz
output/waterfox-musl-wayland-avx2-6.7.5.tar.xz.sha256
output/build-metadata-wayland-avx2.env
```

The `.sha256` file contains the hash. The `.env` file records the upstream tag, commit, build flavour, CPU tier, and artefact name.

## Rebuilding after the first run

The `waterfox-src/` tree and the `sccache/` directory persist on the host between runs. To rebuild without re-downloading the source, skip the `fetch-upstream.sh` step and re-run the `podman run` command. To rebuild from a clean source tree, re-run `fetch-upstream.sh` first.

To build a different variant, change `FLAVOUR` and/or `CPU_TIER`. The `build/` directory is shared and is keyed by nothing in particular, so if you switch variants, clear it first to avoid stale object files:

```bash
rm -rf build/*
```

To pin a specific Waterfox or NSPR version:

```bash
scripts/fetch-upstream.sh ./waterfox-src 6.7.4
podman run ... -e NSPR_VERSION=4.39 ...
```

## Repository layout

```
.
├── Dockerfile Alpine edge toolchain image
├── LICENSE BSD 2-Clause (build tooling)
├── LICENSE-MPL MPL 2.0 (Waterfox source)
├── NOTICE Attribution and licensing summary
├── README.md
├── mozconfig.template mozconfig with @PLACEHOLDER@ substitutions
├── nspr/
│ ├── build.sh Builds NSPR with musl large-file support
│ └── patches/
│   └── musl-largefile.patch Fixes PR_Seek64 capped at 2 GiB
├── patches/
│ ├── disable-glean-sdk.patch
│ ├── fix-hunspell-header.patch
│ ├── fix-musl-redefined-prctl_mm_map.patch
│ ├── fix-product-name.patch
│ ├── fix-rust-target.patch
│ ├── manifest.txt Patch list with descriptions (used by CI)
│ └── sandbox-sched_setscheduler.patch
├── scripts/
│ ├── build.sh Applies patches, builds NSPR and Waterfox
│ ├── fetch-upstream.sh Resolves and clones the Waterfox tag
│ ├── make-source-tarball.sh Produces the MPL-compliant source tarball
│ └── package.sh Renames artefact and emits checksum
└── .github/
  └── workflows/
    └── build.yml matrix build and release workflow
```

## Patches applied

Waterfox's source is written for glibc. Alpine's musl patch set for Firefox covers most of the gap, but Waterfox differs in a few places. The patches in `patches/` handle:

| Patch | Description |
|-------|-------------|
| `disable-glean-sdk.patch` | Removes the optional glean-sdk Python dependency from `python/sites/mach.txt`; it cannot be built on musl. |
| `fix-hunspell-header.patch` | Guards the `myopen` declaration in hunspell's `csutil.hxx` behind `#ifndef MOZILLA_CLIENT`, matching the guard already on the definition in `csutil.cxx`. |
| `fix-musl-redefined-prctl_mm_map.patch` | Drops the `<linux/prctl.h>` include in libwebrtc; musl's `<sys/prctl.h>` already defines `prctl_mm_map` and the Linux header conflicts with it. |
| `fix-product-name.patch` | Sets `MOZ_APP_NAME` and `MOZ_APP_DISPLAYNAME` to `waterfox` / `Waterfox` for the unofficial branding. |
| `fix-rust-target.patch` | Replaces Mozilla's automatic rustc target detection with a `RUST_TARGET` environment override. |
| `sandbox-sched_setscheduler.patch` | Allows `sched_setscheduler` in the GMP and RDD sandbox policies (upstream bug 1657849). |

NSPR is built from source with `musl-largefile.patch` because Alpine's system
NSPR caps `PR_Seek64` at 2 GiB, which breaks chunked uploads.

## Toolchain image

The Dockerfile is based on `alpine:edge`. Alpine edge is used rather than a stable release because Waterfox 153 ESR requires NSS 3.125 or newer and Clang 22, neither of which is available in Alpine's stable branches at the time of writing.

Pinning Alpine edge makes the image non-reproducible across time. If you need bit-identical rebuilds, pin the Dockerfile base to a specific digest:

```
FROM alpine:edge@sha256:...
```

## Runner prerequisites

The GitHub Actions workflow expects a self-hosted runner with the label
`waterfox-builder`. Provision once:

- `podman` installed, runner user in the `podman` group
- `git`, `curl`, `tar`, `patch` on the host
- Network access to `archive.mozilla.org`, `github.com`, `api.github.com`,
  `codeload.github.com`
- 30 GB RAM minimum, 60 GB free disk for the sccache directory and object
  files

The workflow does not install the container runtime. That is a host-level responsibility.

sccache is used to speed up repeated builds. Its cache lives under the runner's tool cache and is keyed by CPU tier. The two toolkit flavours share a cache within a tier, because the toolkit difference affects only a small fraction of the code.

## Licensing

This project builds Waterfox from source. Waterfox is distributed under the Mozilla Public License 2.0. The build scripts, patches, and configuration in this repository are provided under the BSD2-clause license.

This is not an official Waterfox release.
For bug reports about the browser itself, use the [upstream issue tracker](https://github.com/BrowserWorks/waterfox/issues).
For issues with the musl build specifically, open an issue [here](../../issues).
