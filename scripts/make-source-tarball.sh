#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: make-source-tarball.sh <version>}"
SRC_DIR="${SRC_DIR:-/build/waterfox}"
OUT_DIR="${OUT_DIR:-/output}"

log() { printf '[source-tarball] %s\n' "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

[ -d "${SRC_DIR}" ] || die "source tree not found at ${SRC_DIR}"
mkdir -p "${OUT_DIR}"

TARBALL="${OUT_DIR}/waterfox-${VERSION}-patched-source.tar.xz"

STAGE=$(mktemp -d)
trap 'rm -rf "${STAGE}"' EXIT

# Hard-link the tree into a staging directory with the versioned name.
# Hard links mean the copy is nearly free and uses no extra disk space.
cp -al "${SRC_DIR}" "${STAGE}/waterfox-${VERSION}"

# Remove things that should not ship, from the staging copy only.
rm -f "${STAGE}/waterfox-${VERSION}/.waterfox-version"
rm -rf "${STAGE}/waterfox-${VERSION}/.git"
rm -f "${STAGE}/waterfox-${VERSION}/.mozconfig"

# Archive from the staging directory.
tar -C "${STAGE}" -cJf "${TARBALL}" "waterfox-${VERSION}"

sha256sum "${TARBALL}" >"${TARBALL}.sha256"

log "Wrote ${TARBALL}"
log "Wrote ${TARBALL}.sha256"
