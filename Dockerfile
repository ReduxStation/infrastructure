##############################################################################
# Stage 1 — BYOND base
#   Debian 12 slim + i386 multiarch + BYOND 516.1680 installed via the
#   official BYOND Linux zip ("make here"). All subsequent stages that need
#   DreamMaker or DreamDaemon inherit from this.
##############################################################################
FROM debian:12-slim AS byond_base

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        make \
        libc6:i386 \
        libstdc++6:i386 \
        libgcc-s1:i386 \
        libssl3:i386 \
        libcurl4:i386 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
        "https://www.byond.com/download/build/516/516.1680_byond_linux.zip" \
        -o /tmp/byond.zip \
    && cd /tmp \
    && unzip -q byond.zip \
    && cd byond \
    && make here \
    && mv /tmp/byond /opt/byond \
    && rm -f /tmp/byond.zip

ENV PATH="/opt/byond/bin:${PATH}"
ENV BYOND_HOME="/opt/byond"
ENV LD_LIBRARY_PATH="/opt/byond/bin"

##############################################################################
# Stage 2 — Build rust_g from source (32-bit, Debian 12)
#   Compiling from source guarantees GLIBC compatibility. Only the features
#   actually used by this codebase are enabled: dmi, git, log.
##############################################################################
FROM debian:12-slim AS rust_g_builder

# gcc-multilib gives us the 32-bit linker stubs needed for i686 cross-builds.
# No i386 arch or OpenSSL needed — we only build dmi+log which are pure-Rust.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        file \
        git \
        gcc \
        gcc-multilib \
    && rm -rf /var/lib/apt/lists/*

# gcc-multilib adds -m32 support to plain gcc but does NOT create an
# i686-linux-gnu-gcc binary. Cargo looks for exactly that name, so create
# a thin wrapper so the linker lookup succeeds.
RUN printf '#!/bin/sh\nexec gcc -m32 "$@"\n' \
        > /usr/local/bin/i686-linux-gnu-gcc \
    && chmod +x /usr/local/bin/i686-linux-gnu-gcc

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal \
    && /root/.cargo/bin/rustup target add i686-unknown-linux-gnu

ENV PATH="/root/.cargo/bin:${PATH}"
# gcc-multilib on Debian exposes the 32-bit linker as i686-linux-gnu-gcc, not plain gcc.
# Using plain gcc here would silently produce an x86_64 .so that BYOND (32-bit) cannot load.
ENV CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER=i686-linux-gnu-gcc
ENV PKG_CONFIG_ALLOW_CROSS=1

RUN git clone --depth=1 --branch=0.4.10 \
        https://github.com/tgstation/rust-g /rust-g

WORKDIR /rust-g

# 0.4.10 bug: GenericImageError variant in src/error.rs references ImageError
# from the `image` crate which is not compiled when the dmi feature is excluded.
# Same class of bug as 6.1.0's Dmi variant. Patch it before building.
RUN sed -i '/GenericImageError(#\[from\] ImageError)/i\    #[cfg(feature = "dmi")]' src/error.rs

RUN cargo build --release \
        --target=i686-unknown-linux-gnu \
        --no-default-features \
        --features="log"

RUN cp target/i686-unknown-linux-gnu/release/librust_g.so /librust_g.so

# Hard gate: fail the build now if the output is wrong arch or has missing deps.
# A 64-bit .so will be silently ignored by BYOND's 32-bit process at runtime.
RUN file /librust_g.so | grep -q "32-bit" \
    || { echo "BUILD ERROR: librust_g.so is not 32-bit — BYOND will refuse to load it"; exit 1; }
RUN ldd /librust_g.so; \
    ldd /librust_g.so | grep -q "not found" \
    && { echo "BUILD ERROR: librust_g.so has missing runtime deps (see ldd above)"; exit 1; } || true

##############################################################################
# Stage 3 — Build tgui-next bundle
#   yarn install + production webpack build.  Must run BEFORE the DM
#   compile so the HTML/JS bundle is included in the .rsc.
##############################################################################
FROM node:12-slim AS tgui_builder

WORKDIR /tgui-next

# Copy full tgui-next tree (node_modules excluded via .dockerignore)
COPY tgui-next/ .

RUN yarn install --frozen-lockfile \
    && yarn run build

##############################################################################
# Stage 4 — DM compile
#   Full source tree + fresh tgui bundle → DreamMaker → deploy.sh
##############################################################################
FROM byond_base AS dm_compiler

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tgstation

# Bring in the entire source tree (node_modules, data, etc. excluded by .dockerignore)
COPY . .

# Overlay the freshly built tgui bundle over whatever is in the source tree
COPY --from=tgui_builder \
    /tgui-next/packages/tgui/public/ \
    tgui-next/packages/tgui/public/

RUN DreamMaker -max_errors 0 hippiestation.dme \
    && bash tools/deploy.sh /deploy

##############################################################################
# Stage 5 — Runtime image
#   Minimal Debian 12 + BYOND bins (via byond_base) + native libs +
#   compiled game assets.  Config and data live in named volumes.
##############################################################################
FROM byond_base AS runtime

WORKDIR /tgstation

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        mariadb-client \
        netcat-openbsd \
        libmariadb3:i386 \
        libsqlite3-0:i386 \
        zlib1g:i386 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /root/.byond/bin \
    && ln -sf /usr/lib/i386-linux-gnu/libmariadb.so.3 \
              /usr/lib/i386-linux-gnu/libmariadb.so.2

# BSQL: download pre-built and scatter to every location dlopen("BSQL") might search,
# using every filename variant BYOND might try (BSQL, BSQL.so, libBSQL.so).
RUN curl -fsSL \
        "https://github.com/tgstation/BSQL/releases/download/v1.4.0.0/libBSQL.so" \
        -o /tmp/libBSQL.so \
    && cp /tmp/libBSQL.so /tgstation/libBSQL.so \
    && cp /tmp/libBSQL.so /tgstation/BSQL.so \
    && cp /tmp/libBSQL.so /tgstation/BSQL \
    && cp /tmp/libBSQL.so /opt/byond/bin/libBSQL.so \
    && cp /tmp/libBSQL.so /opt/byond/bin/BSQL.so \
    && cp /tmp/libBSQL.so /opt/byond/bin/BSQL \
    && cp /tmp/libBSQL.so /opt/byond/libBSQL.so \
    && cp /tmp/libBSQL.so /opt/byond/BSQL.so \
    && cp /tmp/libBSQL.so /opt/byond/BSQL \
    && cp /tmp/libBSQL.so /usr/lib/i386-linux-gnu/libBSQL.so \
    && cp /tmp/libBSQL.so /usr/local/lib/libBSQL.so \
    && rm /tmp/libBSQL.so

# quickwrite: buffered file I/O library used by the demo recording subsystem.
# Must be 32-bit (i686) to match BYOND's 32-bit process.
RUN curl -fsSL \
        "https://raw.githubusercontent.com/Acensti/HippieStation/master/libquickwrite.so" \
        -o /tmp/libquickwrite.so \
    && cp /tmp/libquickwrite.so /tgstation/libquickwrite.so \
    && cp /tmp/libquickwrite.so /opt/byond/bin/libquickwrite.so \
    && cp /tmp/libquickwrite.so /usr/lib/i386-linux-gnu/libquickwrite.so \
    && rm /tmp/libquickwrite.so

# Compiled game (hippiestation.dmb, .rsc, _maps, sound, strings, icons)
COPY --from=dm_compiler /deploy ./

# rust_g: scatter to every location dlopen("rust_g") might search.
# On Linux, dlopen("rust_g") searches LD_LIBRARY_PATH and standard lib paths —
# it does NOT look in the current working directory unless you pass "./rust_g".
# BYOND 515+ uses call_ext which calls dlopen with the bare name "rust_g", so we
# need the file present in LD_LIBRARY_PATH (/opt/byond/bin) and the game dir.
COPY --from=rust_g_builder /librust_g.so /tgstation/rust_g
COPY --from=rust_g_builder /librust_g.so /tgstation/rust_g.so
COPY --from=rust_g_builder /librust_g.so /tgstation/librust_g.so
COPY --from=rust_g_builder /librust_g.so /opt/byond/bin/rust_g
COPY --from=rust_g_builder /librust_g.so /opt/byond/bin/rust_g.so
COPY --from=rust_g_builder /librust_g.so /opt/byond/bin/librust_g.so
COPY --from=rust_g_builder /librust_g.so /opt/byond/rust_g
COPY --from=rust_g_builder /librust_g.so /opt/byond/rust_g.so
COPY --from=rust_g_builder /librust_g.so /opt/byond/librust_g.so
COPY --from=rust_g_builder /librust_g.so /usr/lib/i386-linux-gnu/rust_g.so
COPY --from=rust_g_builder /librust_g.so /usr/lib/i386-linux-gnu/librust_g.so
COPY --from=rust_g_builder /librust_g.so /usr/local/lib/rust_g.so
COPY --from=rust_g_builder /librust_g.so /usr/local/lib/librust_g.so

COPY docker/game/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/tgstation/config", "/tgstation/data"]

EXPOSE 1337

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=18 \
    CMD nc -z localhost 1337 || exit 1

ENTRYPOINT ["/entrypoint.sh"]