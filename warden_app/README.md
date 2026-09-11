# Wcash Warden Testnet

`warden_app` is a clean, isolated Flutter application for Android, iOS, Linux,
macOS, and Windows. It does not import or link the repository's inherited app
or native plugin. Its separately named `rust_lib_wcash_warden` Cargokit plugin
builds the narrow `warden_app/rust` flutter_rust_bridge wrapper, which depends
only on `../rust_warden` for Wcash product logic.

This first milestone deliberately supports only:

- the frozen Wcash Testnet identity (`TWC`, 8 decimals);
- attestation of `https://wallet-testnet.wcashexplorer.com`; and
- in-memory derivation of a `wutest1…` Wcash Unified Address with an Orchard
  receiver for private Ironwood payouts, and a transparent `WT…` mining
  address, from an English BIP-39 phrase supplied for Testnet integration only.

It includes the storage foundation for the receive-wallet milestone: a fixed
Application Support root and fail-closed operating-system secure storage for a
single mnemonic. The secure write is read back before wallet initialization can
continue, errors never include secret material, and deletion is also verified.
The UI does **not yet** create or restore a persistent wallet, synchronize
blocks or balances, show transaction history, construct transactions, sign,
broadcast, or support a second network or configurable server. The address
screen is a preview for integration testing, not a wallet release. Do not use
it to custody funds.

Future persistent state is reserved under:

- database: `wcash-warden-wcashtestnet-v5.sqlite3`
- secure scope: `com.wcashwallet.warden.testnet.secure-store`

Apple stores the mnemonic in a non-synchronizable, this-device-only keychain
item available only while unlocked. Android backup and device transfer are
disabled and explicitly exclude both the secure preferences and wallet DB
namespace. Linux uses libsecret through a vendored plugin fork that keeps the
native schema name in stable owned storage. Windows uses a vendored DPAPI
plugin fork with serialized, same-directory atomic replacement, a validated
recovery copy, and non-destructive corrupt-read handling. Both forks retain
their upstream licenses and include focused regression tests under `vendor/`.
Linux and Windows also enforce one Warden process per local user profile so
whole-store updates cannot race across desktop launches. Linux combines the
desktop session identity with a user-data advisory lock; Windows holds an
exclusive file handle in local application data. The operating system releases
both locks if the process exits or crashes.

## Development

Use the repository-pinned Flutter version through FVM:

```sh
fvm flutter pub get
flutter_rust_bridge_codegen generate
fvm flutter analyze
fvm flutter test
tool/verify_product_boundary.sh
```

Linux builds require the system `libsecret-1` development package used by
`flutter_secure_storage_linux`.

The release-safe default chooses mobile metrics on Android/iOS and desktop
metrics elsewhere. `WARDEN_FORM_FACTOR=desktop|mobile` remains an optional,
deterministic override for development and tests:

```sh
fvm flutter build apk
fvm flutter build ios --simulator
```

The application ID is `com.wcashwallet.warden.testnet`. Linux and Windows use
the executable name `wcash-warden-testnet`; macOS uses the same executable
inside `Wcash Warden Testnet.app`. Android release output remains unsigned and
must fail distribution until a dedicated Wcash release key is configured.

The Cargokit copy retains its upstream Apache-2.0 license in
`rust_builder/cargokit/LICENSE`.
