FROM tgstation/server:latest

# Install i386 (32-bit) runtime dependencies required by BYOND and its
# native extensions (rust_g, libBSQL.so, libquickwrite.so).
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libmariadb3:i386 \
        libsqlite3-0:i386 \
        libstdc++6:i386 \
        libssl3:i386 \
        libcurl4:i386 \
        zlib1g:i386 \
    && ln -sf /usr/lib/i386-linux-gnu/libmariadb.so.3 \
              /usr/lib/i386-linux-gnu/libmariadb.so.2 \
    && rm -rf /var/lib/apt/lists/*
