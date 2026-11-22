# Headless WoW client simulator (https://github.com/wowless/wowless, MIT) used by
# `./dev sim`: loads the addon into Blizzard's real UI code, fires login events,
# clicks around, and reports Lua errors. Heavy (several minutes to build, >1 GB),
# so it is a separate image that is only built the first time `./dev sim` runs.
# The WoW client data it simulates is downloaded at image build time.
FROM python:3.13-bookworm

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      autoconf-archive build-essential ca-certificates git ninja-build curl zip unzip tar pkg-config linux-libc-dev \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir cmake jinja2 \
 && git config --system --add safe.directory '*'

# WOWLESS_PRODUCT selects the game flavor: wowf = WoW: Forever, wow = Retail, wow_classic, ...
ARG WOWLESS_REF=c695caab195f06367aec63b9c7ac86241b1f390d
ARG WOWLESS_PRODUCT=wowf

RUN git init -q /wowless && cd /wowless \
 && git fetch -q --depth 1 https://github.com/wowless/wowless "${WOWLESS_REF}" && git checkout -q FETCH_HEAD \
 && git submodule update --init --depth 1
WORKDIR /wowless

# The pinned wowless commit knows one client build per product, and Blizzard's CDN
# stops serving a build's data once a newer one is out. These override the build
# wowless fetches (empty = use wowless's own). Current values:
#   curl -s https://us.version.battle.net/v2/products/<product>/versions
# -> BuildConfig is the hash, BuildId the build number. WOW_DBDEFS_REF is a commit
# of github.com/wowdev/wowdbdefs recent enough to describe that build.
ARG WOW_BUILD=71037
ARG WOW_BUILD_HASH=0acab1e6aa41b46165d2ca66853b417b
ARG WOW_DBDEFS_REF=3a7954cfb8ee4f1132c83cd1859753294ee8964b
RUN if [ -n "${WOW_BUILD}" ]; then \
      git -C vendor/dbdefs fetch -q --depth 1 https://github.com/wowdev/wowdbdefs "${WOW_DBDEFS_REF}" \
      && git -C vendor/dbdefs checkout -q FETCH_HEAD; \
      f="data/products/${WOWLESS_PRODUCT}/build.yaml"; \
      sed -i "s/^build: .*/build: '${WOW_BUILD}'/; s/^hash: .*/hash: ${WOW_BUILD_HASH}/" "$f"; cat "$f"; \
    fi
RUN cmake --preset default
RUN cmake --build --preset default --target "wowless_${WOWLESS_PRODUCT}" "${WOWLESS_PRODUCT}" \
 && chmod -R a+rwX /wowless
ENV WOWLESS_PRODUCT=${WOWLESS_PRODUCT} HOME=/tmp
