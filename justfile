# The strings CI runs are the strings you run. If these diverge, the gate stops
# predicting local behaviour and a green local build means nothing.
#
# STACK_FLAGS is empty locally; CI sets it once after making system-GHC global.

default: seam build test drift

# CFMM-01 seam guard. Cheap ONLY when .stack-work is warm (~0.3s); a cold tree
# costs ~119s. CI must restore its cache before this runs.
seam:
    ./scripts/seam-guard.sh

# Proves the guard actually fires. Runs in a scratch copy; never mutates the tree.
seam-negative:
    ./scripts/seam-negative-test.sh

# PROTO-04. The type-level analogue of seam-negative: proves a JSON number and a raw
# construction both FAIL TO COMPILE, in two distinguishable ways.
hex-only:
    ./scripts/hex-only-guard.sh

build:
    stack build --system-ghc --no-install-ghc --test --no-run-tests --pedantic

test:
    stack build --system-ghc --no-install-ghc --test --pedantic

# Committed .cabal files must match package.yaml.
drift:
    ./scripts/hpack-drift.sh

# DIST-06. The full local assertion: the forge on THIS box is the pinned forge, by commit SHA.
# CI runs the SAME script with --check-format (see .github/workflows/ci.yml) -- one script, two
# callers, so the two sides cannot drift apart.
foundry-pin:
    ./scripts/foundry-pin.sh

# Local mirror of the CI `image` job (01-06 / DIST-04). The tag is a fixed local
# name -- CI computes a lowercase, slash-free ref from github.repository, which is
# not reproducible off a runner. Same Dockerfile, same context, same smoke command.
image:
    docker build -f docker/Dockerfile -t evm-spec-bridge:local .

# A Dockerfile that builds but produces a binary that cannot start is a false green.
# CI runs this exact command against the loaded image; so do we.
image-run:
    docker run --rm evm-spec-bridge:local --version
