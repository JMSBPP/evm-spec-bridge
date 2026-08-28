# Phase 3 Summary

## What Phase 3 proved

1. **Discrimination by tag** — `just discriminate` (Discrimination.t.sol)
2. **Boundary survival** — `just boundary-sweep` (BoundarySweep.t.sol + cast keccak)
3. **Wedged oracle red** — `just wedge-red` (~47s NEGATIVE stage)
4. **Hex-only wire type** — `just hex-only`
5. **protocolVersion on all constructors** — `just version-sweep`

## Locked decisions

- Envelope: `abi.encode(uint16 version, uint8 tag, bytes body)`; tags 0x01/0x02/0x03; 0x00 reserved
- `protocolVersion = 1` once in `Bridge.Protocol`
- `solidity/` permanent; oracle-stub is a Stack component

## What Phase 3 did NOT prove

- Arrays and three-encoding comparison unguarded until Phase 8
- `web3-solidity` correctness assumed, not verified
- Wedge bounds OUTCOME only — **45s COST survives until Phase 5 SRV-04**
- One host/OS; master vs 1.5.1 wrapping difference unverified

## Owed

- `gams-evm-transport`: array results on `vm.rpc` path when Phase 8 runs

## Hand-written Solidity Phase 9 replaces

- `solidity/src/Vm.sol`
- `solidity/src/SpecOracle.sol`
- `solidity/test/Discrimination.t.sol`
- `solidity/test/BoundarySweep.t.sol`
- `solidity/test/WedgeRed.t.sol`
