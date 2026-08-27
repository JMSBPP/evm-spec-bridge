# evm-spec-bridge

A Haskell JSON-RPC service that lets a Foundry test call a typed Haskell specification as an
oracle in the middle of a `forge test` run. The spec answers what a contract *should* do; the
test compares that to what it *did*; a divergence fails the build.

**Core value:** spec success, spec rejection, and transport failure are never conflated.

- Canonical: `d2p-finance/evm-spec-bridge` — receives pull requests only.
- Development fork: `JMSBPP/evm-spec-bridge` — `develop` is the integration branch.

Planning, requirements, roadmap and research live in `.planning/`.