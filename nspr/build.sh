#!/bin/sh
#
# Build NSPR against musl with 64-bit off_t support.
#
# Usage:
#   nspr/build.sh [INSTALL_PREFIX]
#
#   INSTALL_PREFIX  Where to install the result. Default: /tmp/nspr-install/usr

set -eu

# ---------------------------------------------------------------------------
# Definitions (must come before any use)
# ---------------------------------------------------------------------------
NSPR_BASE="https://archive.mozilla.org/pub/nspr/releases"

SRC_DIR="/tmp/nspr"
BUILD_DIR="/tmp/nspr/build"
PATCH="/build/nspr/patches/musl-largefile.patch"

log() { printf '[nspr] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit "${2:-2}"; }

PREFIX="${1:-/tmp/nspr-install/usr}"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if [ -n "${NSPR_VERSION:-}" ]; then
    log "Using caller-pinned NSPR version: ${NSPR_VERSION}"
else
    log "Resolving latest NSPR version"
    NSPR_VERSION=$(curl -fsSL "${NSPR_BASE}/" \
        | grep -oE '/pub/nspr/releases/v[0-9]+(\.[0-9]+)*/' \
        | sed -e 's|.*/v||' -e 's|/$||' \
        | sort -rV \
        | head -1) \
        || die "failed to query NSPR release listing" 1
    [ -n "${NSPR_VERSION}" ] || die "could not parse an NSPR version" 1
fi

NSPR_URL="${NSPR_BASE}/v${NSPR_VERSION}/src/nspr-${NSPR_VERSION}.tar.gz"

log "NSPR version: ${NSPR_VERSION}"
log "Tarball URL: ${NSPR_URL}"

# ---------------------------------------------------------------------------
# 1. Preconditions
# ---------------------------------------------------------------------------
[ -f "${PATCH}" ] || die "missing patch: ${PATCH}" 1

for tool in curl tar patch make cc; do
    command -v "${tool}" >/dev/null 2>&1 || die "missing tool: ${tool}" 1
done

# ---------------------------------------------------------------------------
# 2. Fetch and extract
# ---------------------------------------------------------------------------
if [ -f "${SRC_DIR}/nspr/pr/include/md/_linux.h" ]; then
    log "Source already extracted at ${SRC_DIR}"
else
    log "Fetching NSPR ${NSPR_VERSION}"
    rm -rf "${SRC_DIR}"
    mkdir -p "${SRC_DIR}"
    curl -fsSL "${NSPR_URL}" | tar xz --strip 1 -C "${SRC_DIR}" \
        || die "download or extract failed"
fi

# ---------------------------------------------------------------------------
# 3. Apply the musl large-file patch
# ---------------------------------------------------------------------------
if grep -q "_PR_HAVE_LARGE_OFF_T" "${SRC_DIR}/nspr/pr/include/md/_linux.h"; then
    log "Large-file patch already applied"
else
    log "Applying musl large-file patch"
    patch -p1 -t -N --forward -d "${SRC_DIR}/nspr" < "${PATCH}" \
        || die "patch failed"
fi

# ---------------------------------------------------------------------------
# 4. Configure
# ---------------------------------------------------------------------------
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

export CFLAGS="${CFLAGS:-} \
    -D_PR_POLL_AVAILABLE \
    -D_PR_HAVE_LARGE_OFF_T \
    -D_PR_INET6 \
    -D_PR_HAVE_INET_NTOP \
    -D_PR_HAVE_GETHOSTBYNAME2 \
    -D_PR_HAVE_GETADDRINFO \
    -D_PR_INET6_PROBE"

log "Configuring NSPR with prefix ${PREFIX}"
../nspr/configure \
    --prefix="${PREFIX}" \
    --disable-debug \
    --enable-optimize \
    --enable-ipv6 \
    --enable-64bit \
    || die "configure failed"

# ---------------------------------------------------------------------------
# 5. Build and install
# ---------------------------------------------------------------------------
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
log "Building NSPR with ${JOBS} jobs"
make -j"${JOBS}" || die "make failed"

log "Installing NSPR"
make install || die "make install failed"

# ---------------------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------------------
PC="${PREFIX}/lib/pkgconfig/nspr.pc"
[ -f "${PC}" ] || die "nspr.pc not found at ${PC}"

log "Installed NSPR to ${PREFIX}"
printf 'NSPR_PREFIX=%s\n' "${PREFIX}"
printf 'NSPR_PKGCONFIG_DIR=%s/lib/pkgconfig\n' "${PREFIX}"
