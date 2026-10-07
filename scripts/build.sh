#!/bin/sh
set -eu

# ---------------------------------------------------------------------------
# Configuration from environment
# ---------------------------------------------------------------------------
FLAVOUR="${FLAVOUR:-wayland}"
CPU_TIER="${CPU_TIER:-baseline}"
SRC_DIR="${SRC_DIR:-/build/waterfox}"
OUT_DIR="${OUT_DIR:-/output}"

log() { printf '[build] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

[ -d "${SRC_DIR}" ] || die "source tree not found at ${SRC_DIR}"
mkdir -p "${OUT_DIR}"

WATERFOX_VERSION=$(cat "${SRC_DIR}/.waterfox-version")
WATERFOX_COMMIT=$(git -C "${SRC_DIR}" rev-parse HEAD)
log "Waterfox ${WATERFOX_VERSION} (${WATERFOX_COMMIT}) — flavour=${FLAVOUR} cpu=${CPU_TIER}"

# ---------------------------------------------------------------------------
# Flavour → toolkit and CPU tier → compiler flags
# ---------------------------------------------------------------------------
case "${FLAVOUR}" in
    x11)     TOOLKIT="cairo-gtk3" ;;
    wayland) TOOLKIT="cairo-gtk3-wayland" ;;
    *) die "unknown FLAVOUR: ${FLAVOUR}" ;;
esac

case "${CPU_TIER}" in
    baseline)
        OPTIMIZE_FLAGS="-march=x86-64-v2 -mtune=haswell -O3 -w"
        RUST_CPU="x86-64-v2" ;;
    avx2)
        OPTIMIZE_FLAGS="-march=x86-64-v3 -mtune=haswell -O3 -w"
        RUST_CPU="x86-64-v3" ;;
    *) die "unknown CPU_TIER: ${CPU_TIER}" ;;
esac

# ---------------------------------------------------------------------------
# Apply musl patches
# ---------------------------------------------------------------------------
cd "${SRC_DIR}"
rm -f .mozconfig

for p in /build/patches/*.patch; do
    [ -f "$p" ] || continue
    log "Applying $(basename "$p")"
    patch -p1 -t -N --forward < "$p" || log "SKIPPED: $(basename "$p")"
done

# Clear vendored cargo checksums (missing .orig files, Mozilla bug 1998885)
find third_party/rust -name .cargo-checksum.json \
    -exec sed -i -e 's/\("files":{\)[^}]*/\1/' {} \;

# ---------------------------------------------------------------------------
# Render mozconfig
# ---------------------------------------------------------------------------
sed -e "s|@TOOLKIT@|${TOOLKIT}|g" \
    -e "s|@OPTIMIZE_FLAGS@|${OPTIMIZE_FLAGS}|g" \
    -e "s|@RUST_CPU@|${RUST_CPU}|g" \
    -e "s|@WATERFOX_VERSION@|${WATERFOX_VERSION}|g" \
    /build/mozconfig.template > .mozconfig

# ---------------------------------------------------------------------------
# Build NSPR
# ---------------------------------------------------------------------------
NSPR_VERSION_ENV="${NSPR_VERSION:-}"
NSPR_OUT=$(NSPR_VERSION="${NSPR_VERSION_ENV}" sh /build/nspr/build.sh)
NSPR_PKGCONFIG=$(printf '%s\n' "${NSPR_OUT}" | sed -n 's|^NSPR_PKGCONFIG_DIR=||p')
[ -n "${NSPR_PKGCONFIG}" ] || die "NSPR build did not report a pkgconfig dir"

export PKG_CONFIG_PATH="${NSPR_PKGCONFIG}:${PKG_CONFIG_PATH:-}"
export RUST_TARGET=x86_64-alpine-linux-musl

# ---------------------------------------------------------------------------
# Build and package
# ---------------------------------------------------------------------------
printf '%s\n' "${WATERFOX_VERSION}" > browser/config/version_display.txt
log "Running ./mach build"
./mach build

# Alpine's linker drops \$ORIGIN from DT_RUNPATH. Restore it so libxul
# finds its sibling libmozsandbox.so at runtime.
log "Setting \$ORIGIN rpath on libxul.so and waterfox"
patchelf --set-rpath '$ORIGIN' /build/obj/dist/bin/libxul.so
patchelf --set-rpath '$ORIGIN' /build/obj/dist/bin/waterfox

log "Running ./mach package"
./mach package

FLAVOUR="${FLAVOUR}" CPU_TIER="${CPU_TIER}" \
WATERFOX_VERSION="${WATERFOX_VERSION}" \
WATERFOX_COMMIT="${WATERFOX_COMMIT}" \
    sh /build/scripts/package.sh
