#!/bin/sh
set -eu

FLAVOUR="${FLAVOUR:-wayland}"
CPU_TIER="${CPU_TIER:-baseline}"
WATERFOX_VERSION="${WATERFOX_VERSION:?WATERFOX_VERSION is required}"
OUT_DIR="${OUT_DIR:-/output}"

log() { printf '[package] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Glob expands here because it is an argument to `set`, not the RHS of an assignment.
set -- /build/obj/dist/*.tar.xz

# If nothing matched, $1 is the literal pattern string.
[ -e "$1" ] || die "no tarball found under /build/obj/dist/"

# If more than one tarball exists, refuse to guess.
[ "$#" -eq 1 ] || die "multiple tarballs found: $*"

SRC="$1"
EXT="tar.xz"

OUTNAME="waterfox-musl-${FLAVOUR}-${CPU_TIER}-${WATERFOX_VERSION}.${EXT}"
DEST="${OUT_DIR}/${OUTNAME}"

log "Copying ${SRC} -> ${DEST}"
cp "${SRC}" "${DEST}"

( cd "${OUT_DIR}" && sha256sum "${OUTNAME}" > "${OUTNAME}.sha256" )

log "Produced ${OUTNAME}"
log "Checksum written to ${OUTNAME}.sha256"

METADATA="${OUT_DIR}/build-metadata-${FLAVOUR}-${CPU_TIER}.env"
{
    printf 'WATERFOX_VERSION=%s\n'  "${WATERFOX_VERSION}"
    printf 'WATERFOX_COMMIT=%s\n'   "${WATERFOX_COMMIT:-unknown}"
    printf 'FLAVOUR=%s\n'           "${FLAVOUR}"
    printf 'CPU_TIER=%s\n'          "${CPU_TIER}"
    printf 'BUILD_DATE=%s\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'ARTEFACT=%s\n'          "${OUTNAME}"
    printf 'SHA256=%s\n'            "$(cut -d' ' -f1 "${OUT_DIR}/${OUTNAME}.sha256")"
} > "${METADATA}"

log "Metadata written to ${METADATA}"

# Emit machine-readable output for the workflow to consume.
printf 'ARTEFACT=%s\n' "${OUTNAME}"
printf 'ARTEFACT_PATH=%s\n' "${DEST}"
