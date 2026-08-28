# THROWAWAY — this directory is deleted in plan 02-05

`spike/` exists to prove ONE thing: that a Foundry `vm.rpc` call reaches a Haskell
process over HTTP. It is deliberately the crudest thing that can answer Foundry.

**It is deleted in plan 02-05.** Deletion is `rm -rf spike/` plus removing the
`spike-server` recipe from the root `justfile`. Nothing else. That is why this is a
self-contained Stack project (`spike/stack.yaml`) rather than a package in the root
`stack.yaml`: CI never builds it, and deletion stays structural instead of becoming a
five-step cleanup that nobody performs.

**Nothing outside `spike/` may depend on anything in here.** The only permitted
reference is the `spike-server` recipe in the root `justfile`, which is removed at the
same time.

**The JSON-RPC envelope in `stub-server/app/Main.hs` is hand-written on purpose.** The
real envelope comes from the `json-rpc` package's Data layer, which arrives in Phase
3/4 where it is actually designed. Putting a library in the path now would add a second
variable to a spike whose entire job is to isolate the transport: if the Foundry test
goes red, it must be the transport and not a codec.
