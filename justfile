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

build:
    stack build --system-ghc --no-install-ghc --test --no-run-tests --pedantic

test:
    stack build --system-ghc --no-install-ghc --test --pedantic

# Committed .cabal files must match package.yaml.
drift:
    ./scripts/hpack-drift.sh
