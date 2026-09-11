#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crate_dir="$(cd "$script_dir/.." && pwd)"
tree_file="$(mktemp)"
api_file="$(mktemp)"
expected_api_file="$(mktemp)"
trap 'rm -f "$tree_file" "$api_file" "$expected_api_file"' EXIT

cargo tree \
  --manifest-path "$crate_dir/Cargo.toml" \
  --locked \
  --edges normal \
  --prefix none >"$tree_file"

for pinned_package in wcash-wallet zcash_protocol zcash_primitives pczt; do
  pinned_lines="$(grep -E "^${pinned_package} v" "$tree_file" || true)"
  if [ -z "$pinned_lines" ]; then
    echo "boundary check failed: $pinned_package is not pinned to the reviewed Wolf revision" >&2
    exit 1
  fi
  if printf '%s\n' "$pinned_lines" | grep -Evq \
    "^${pinned_package} v[^ ]+ \(https://github.com/w-cash/wolf.git\?rev=ea1385c99308e3c00946a3f1cc064a3c3abbf5b0#ea1385c9\)( \(\*\))?$"; then
    echo "boundary check failed: $pinned_package also resolves outside the reviewed Wolf revision" >&2
    exit 1
  fi
done

for forbidden_dependency in \
  rust_lib_zcash_wallet \
  flutter_rust_bridge \
  zcash_voting \
  swapkit; do
  if grep -Fqi "$forbidden_dependency" "$tree_file"; then
    echo "boundary check failed: linked forbidden dependency: $forbidden_dependency" >&2
    exit 1
  fi
done

if grep -Eq '^pub (use|extern|mod|trait|type|union|static|macro)\b|^#\[macro_export\]' \
  "$crate_dir/src/lib.rs"; then
  echo "boundary check failed: unreviewed public item or re-export" >&2
  exit 1
fi

sed -nE \
  's/^[[:space:]]*pub (async )?(fn|struct|enum|const) ([A-Za-z0-9_]+).*/\3/p' \
  "$crate_dir/src/lib.rs" | sort >"$api_file"

printf '%s\n' \
  DerivedAddresses \
  EndpointAttestation \
  NetworkIdentity \
  WardenError \
  attest_testnet_endpoint \
  derive_testnet_addresses_from_mnemonic \
  network_identity | sort >"$expected_api_file"

if ! diff -u "$expected_api_file" "$api_file"; then
  echo "boundary check failed: public crate-root API changed without allowlist review" >&2
  exit 1
fi

echo "rust_warden boundary verified"
