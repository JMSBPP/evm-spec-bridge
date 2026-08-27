# syntax=docker/dockerfile:1
# ---------------------------------------------------------------- builder ---
# haskell:9.10.3-bookworm ships Stack and a matching GHC (0.67GB). The 9.10.3
# tag is not chosen -- it is inherited from LTS 24.55's resolver.compiler.
FROM haskell:9.10.3-bookworm AS builder
WORKDIR /build

# NOTE: no cairo/pango dev headers are installed here. Phase 1 builds ONLY the
# transport executable, which does not depend on cfmm-adapter and therefore
# never reaches cfmm-vol-markets-spec or its plot sublibrary. Anything that
# builds the adapter DOES need libcairo2-dev libpango1.0-dev libglib2.0-dev
# pkg-config -- see 01-01-PROBE-NOTES.md.

# .cabal-only dependency layer, so a source edit does not rebuild dependencies.
# Deliberately NO --mount=type=cache here: a BuildKit cache mount is scratch
# space excluded from the committed layer, and /root/.stack is exactly where
# Stack's package DB lives -- mounting it would make this layer store nothing
# and force the source layer to recompile everything from an empty mount.
COPY stack.yaml stack.yaml.lock ./
COPY components/protocol/evm-spec-bridge-protocol.cabal      components/protocol/
COPY components/abi-codec/evm-spec-bridge-abi-codec.cabal    components/abi-codec/
COPY components/jsonrpc/evm-spec-bridge-jsonrpc.cabal        components/jsonrpc/
COPY components/registry/evm-spec-bridge-registry.cabal      components/registry/
COPY components/transport/evm-spec-bridge-transport.cabal    components/transport/
COPY components/codegen/evm-spec-bridge-codegen.cabal        components/codegen/
COPY components/cfmm-adapter/evm-spec-bridge-cfmm-adapter.cabal components/cfmm-adapter/
RUN stack --system-ghc --no-install-ghc build --only-dependencies evm-spec-bridge-transport

COPY . .
RUN stack --system-ghc --no-install-ghc build evm-spec-bridge-transport \
 && mkdir -p /out \
 && cp "$(stack --system-ghc --no-install-ghc path --local-install-root)/bin/evm-spec-bridge" /out/

# ---------------------------------------------------------------- runtime ---
# Contents decided from `ldd`, not from a list: the binary links libm, libgmp,
# libc, ld-linux. Only libgmp is not already in debian-slim.
FROM debian:bookworm-slim AS runtime
# LANG is NOT visible to ldd and is a latent false green: debian-slim ships no
# locale, GHC falls back to ASCII, and the first non-ASCII byte written dies
# with `commitBuffer: invalid argument`. Phase 1's ASCII --version would pass.
ENV LANG=C.UTF-8
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgmp10 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 --user-group bridge
COPY --from=builder /out/evm-spec-bridge /usr/local/bin/evm-spec-bridge
USER bridge
ENTRYPOINT ["/usr/local/bin/evm-spec-bridge"]
CMD ["--version"]
