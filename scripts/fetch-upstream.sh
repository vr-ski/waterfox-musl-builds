#!/bin/sh
#
# Resolve the latest Waterfox release tag and prepare the source tree.
#
# Usage:
#   fetch-upstream.sh [TARGET_DIR] [TAG]
#
#   TARGET_DIR  Where to clone or update the source. Default: ./waterfox-src
#   TAG         Specific tag to fetch. Default: latest GitHub release.
#
# Writes the resolved tag to $TARGET_DIR/../.waterfox-version so downstream
# scripts can read it without re-querying the API.
#
# Exit codes:
#   0  success
#   1  API query failed
#   2  git operation failed

set -eu

REPO="BrowserWorks/waterfox"
TARGET="${1:-./waterfox-src}"
[ "${TARGET#/}" = "${TARGET}" ] && TARGET="${PWD}/${TARGET}"
WANT_TAG="${2:-}"
VERSION_FILE="${TARGET}/.waterfox-version"

log() { printf '[fetch-upstream] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# 1. Resolve the tag
# ---------------------------------------------------------------------------
if [ -n "${WANT_TAG}" ]; then
    TAG="${WANT_TAG}"
    log "Using caller-provided tag: ${TAG}"
else
    log "Querying GitHub for the latest release of ${REPO}"
    TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1) \
        || die "GitHub API query failed" 1

    [ -n "${TAG}" ] || die "API returned no tag_name" 1
    log "Latest release tag: ${TAG}"
fi

# ---------------------------------------------------------------------------
# 2. Prepare the source tree
# ---------------------------------------------------------------------------
# Waterfox's .gitmodules uses SSH URLs. Inside a container without SSH keys,
# plain 'git submodule update' fails with publickey errors. Rewrite globally
# for this invocation only.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf"
export GIT_CONFIG_VALUE_0="git@github.com:"

if [ -d "${TARGET}/.git" ]; then
    cd "${TARGET}"
    git fetch --depth 1 origin "refs/tags/${TAG}:refs/tags/${TAG}"
    git checkout --force "${TAG}"
    git clean -fdx
    git submodule sync --recursive
    git submodule foreach --recursive 'git reset --hard && git clean -fdx'
    git submodule update --init --recursive
    grep -qxF '.waterfox-version' "${TARGET}/.git/info/exclude" 2>/dev/null \
    || echo '.waterfox-version' >> "${TARGET}/.git/info/exclude"
    printf '%s\n' "${TAG}" > "${VERSION_FILE}"
else
    git clone \
        -c url."https://github.com/".insteadOf="git@github.com:" \
        -c advice.detachedHead=false \
        --recurse-submodules \
        --shallow-submodules \
        --depth 1 \
        --branch "${TAG}" \
        "https://github.com/${REPO}.git" "${TARGET}" \
        || die "git clone failed" 2
    cd "${TARGET}"
    git fetch --depth 1 origin "refs/tags/${TAG}:refs/tags/${TAG}" || true
fi
# ---------------------------------------------------------------------------
# 3. Record the resolved identity
# ---------------------------------------------------------------------------
COMMIT=$(git rev-parse "refs/tags/${TAG}^{commit}")

printf '%s\n' "${COMMIT}" > "${TARGET}/.waterfox-commit"
printf '%s\n' "${TAG}" > "${VERSION_FILE}"

log "Tag:    ${TAG}"
log "Commit: ${COMMIT}"
log "Tree:   $(pwd)"
log "Wrote ${VERSION_FILE}"

# Emit machine-readable values on stdout for use by callers.
#printf 'WATERFOX_VERSION=%s\n' "${TAG}"
#printf 'WATERFOX_COMMIT=%s\n' "${COMMIT}"
