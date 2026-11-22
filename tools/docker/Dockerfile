# Scry dev toolchain. Everything `./dev` runs happens inside this image, so the
# toolchain is identical on Linux, WSL, Windows (Docker Desktop) and CI.
# The image is rebuilt automatically by ./dev when anything in tools/docker/ changes.
FROM debian:bookworm-slim

ARG TARGETARCH
ARG LUALS_VERSION=3.19.2
ARG STYLUA_VERSION=2.6.0
ARG LUACHECK_VERSION=1.2.0
ARG BUSTED_VERSION=2.2.0

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip build-essential ripgrep \
      lua5.1 liblua5.1-0-dev luarocks \
      python3 python3-jsonschema \
 && rm -rf /var/lib/apt/lists/*

RUN luarocks install luacheck ${LUACHECK_VERSION} \
 && luarocks install busted ${BUSTED_VERSION}

RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      arm64) ls_arch=arm64; sl_arch=aarch64 ;; \
      *)     ls_arch=x64;   sl_arch=x86_64 ;; \
    esac; \
    mkdir -p /opt/luals; \
    curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/${LUALS_VERSION}/lua-language-server-${LUALS_VERSION}-linux-${ls_arch}.tar.gz" \
      | tar -xz -C /opt/luals; \
    printf '#!/bin/sh\nexec /opt/luals/bin/lua-language-server "$@"\n' > /usr/local/bin/lua-language-server; \
    chmod +x /usr/local/bin/lua-language-server; \
    curl -fsSL -o /tmp/stylua.zip "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-${sl_arch}.zip"; \
    unzip -q /tmp/stylua.zip -d /usr/local/bin; chmod +x /usr/local/bin/stylua; rm /tmp/stylua.zip

# --- WoW API reference data (pinned; bump with `./dev api-update`) ----------
# WOW_UI_BRANCH selects the game flavor: forever = WoW: Forever, live = Retail, classic, ...
ARG WOW_UI_BRANCH=forever
ARG WOW_UI_REF=734f065329cff4992835b01a84f210a297db91b6
ARG WOW_ANNOTATIONS_REF=d0b5b51fac4c52c493371b9b18e66ce604ea4326

RUN set -eu; \
    fetch() { mkdir -p "$2"; cd "$2"; git init -q; git fetch -q --depth 1 "$1" "$3"; git checkout -q FETCH_HEAD; rm -rf .git; }; \
    fetch https://github.com/Gethe/wow-ui-source /opt/wow-api/ui-source "${WOW_UI_REF}"; \
    fetch https://github.com/Ketho/vscode-wow-api /tmp/ketho "${WOW_ANNOTATIONS_REF}"; \
    mv /tmp/ketho/Annotations /opt/wow-api/annotations; \
    mv /tmp/ketho/LICENSE /opt/wow-api/annotations/LICENSE; \
    rm -rf /tmp/ketho

COPY gen_api.lua /opt/wow-api/gen_api.lua
RUN cd /opt/wow-api && lua5.1 gen_api.lua && chmod -R a+rX /opt/wow-api

ENV SCRY_IN_CONTAINER=1 \
    WOW_API_DIR=/opt/wow-api \
    HOME=/tmp
WORKDIR /work
