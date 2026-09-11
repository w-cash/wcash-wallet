# Wcash Warden bridge core

`rust_warden` is an isolated, Testnet-only Rust seam for the future Wcash
Warden Flutter bridge. It is deliberately not connected to Cargokit, Dart, or
any platform build target yet.

The public API is limited to:

- the frozen Wcash Testnet identity;
- deterministic private and transparent mining address derivation from an
  English BIP-39 mnemonic; and
- attestation of the fixed public Wcash Testnet wallet endpoint.

There is no endpoint or network selector, mainnet mode, transaction builder,
broadcast method, swap/voting integration, or access to the legacy Vizor Rust
bridge. `wcash-wallet` is pinned to an exact reviewed Wolf revision.

Run the local gate from the repository root:

```sh
rust_warden/scripts/verify-boundary.sh
```

The live endpoint test is intentionally excluded from the normal deterministic
test suite. Run it explicitly when deployment verification is required:

```sh
cargo test --manifest-path rust_warden/Cargo.toml \
  --test live_endpoint -- --ignored --nocapture
```

