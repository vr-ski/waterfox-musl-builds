FROM alpine:edge

# Build dependencies, aligned with Alpine's firefox-esr APKBUILD plus
# the system libraries we link against via mozconfig.
RUN apk add --no-cache \
    alsa-lib-dev automake bsd-compat-headers cargo cbindgen \
    build-base \
    clang22 clang22-libclang compiler-rt \
    dbus dbus-dev gettext gettext-envsubst gtk+3.0-dev hunspell-dev \
    libevent-dev libjpeg-turbo-dev libnotify-dev libogg-dev icu-dev \
    libtheora-dev libtool libvorbis-dev libvpx-dev libwebp-dev \
    libxcomposite-dev libxt-dev lld22 llvm llvm22-dev libffi-dev \
    m4 mesa-dev mesa-dri-gallium mimalloc2-insecure nasm nodejs \
    nspr-dev nss-dev patchelf pciutils pipewire-dev pulseaudio-dev \
    py3-mozshellutil python3 scudo-malloc sed \
    wasi-sdk wireless-tools-dev xvfb-run zip \
    bash git curl tar patch unzip xz

# cbindgen 0.29.4+ is required by modern Firefox/Waterfox build system.
# Alpine stable ships an older version, so we install it via cargo.
RUN cargo install cbindgen --version 0.29.4 --force

# Upstream LLVM bug workaround: clang-22 searches for WASI builtins under
# wasm32-unknown-wasip1, but wasi-compiler-rt installs them under wasi/.
# Locate the file dynamically since its LLVM version may not match clang's.
RUN mkdir -p /usr/lib/llvm22/lib/clang/22/lib/wasm32-unknown-wasip1 && \
    ln -sf "$(find /usr/lib -name libclang_rt.builtins-wasm32.a | head -1)" \
           /usr/lib/llvm22/lib/clang/22/lib/wasm32-unknown-wasip1/libclang_rt.builtins.a

WORKDIR /build
COPY patches/          /build/patches/
COPY nspr/             /build/nspr/
COPY scripts/          /build/scripts/
COPY mozconfig.template /build/mozconfig.template

CMD ["/bin/bash"]
