#!/usr/bin/env bash
set -euo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tree_file="$(mktemp)"
scan_file="$(mktemp)"
actual_file="$(mktemp)"
expected_file="$(mktemp)"
trap 'rm -f "$tree_file" "$scan_file" "$actual_file" "$expected_file"' EXIT

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq "$text" "$app_dir/$file"; then
    echo "boundary check failed: $file does not contain $text" >&2
    exit 1
  fi
}

require_text pubspec.yaml 'name: wcash_warden'
require_text pubspec.yaml 'flutter_rust_bridge: 2.11.1'
require_text pubspec.yaml 'flutter_secure_storage: 10.0.0'
require_text pubspec.yaml 'path: 1.9.1'
require_text pubspec.yaml 'path_provider: 2.1.5'
require_text pubspec.yaml 'path: rust_builder'
require_text rust_builder/pubspec.yaml 'name: rust_lib_wcash_warden'
require_text rust/Cargo.toml 'name = "rust_lib_wcash_warden"'
require_text rust/Cargo.toml 'flutter_rust_bridge = "=2.11.1"'
require_text rust/Cargo.toml 'rust_warden = { path = "../../rust_warden" }'
require_text flutter_rust_bridge.yaml 'dart_entrypoint_class_name: WardenRust'
require_text flutter_rust_bridge.yaml 'web: false'
require_text android/app/build.gradle.kts \
  'applicationId = "com.wcashwallet.warden.testnet"'
require_text ios/Runner.xcodeproj/project.pbxproj \
  'PRODUCT_BUNDLE_IDENTIFIER = com.wcashwallet.warden.testnet;'
require_text macos/Runner/Configs/AppInfo.xcconfig \
  'PRODUCT_BUNDLE_IDENTIFIER = com.wcashwallet.warden.testnet'
require_text linux/CMakeLists.txt 'set(BINARY_NAME "wcash-warden-testnet")'
require_text windows/CMakeLists.txt 'set(BINARY_NAME "wcash-warden-testnet")'
require_text android/app/src/main/AndroidManifest.xml \
  '<uses-permission android:name="android.permission.INTERNET" />'
require_text android/app/src/main/AndroidManifest.xml \
  'android:allowBackup="false"'
require_text android/app/src/main/res/xml/backup_rules.xml \
  'path="com.wcashwallet.warden.testnet.secure-store.xml"'
require_text android/app/src/main/res/xml/backup_rules.xml \
  'path="wcashtestnet-v5/"'
require_text android/app/src/main/res/xml/data_extraction_rules.xml \
  'path="com.wcashwallet.warden.testnet.secure-store.xml"'
require_text android/app/src/main/res/xml/data_extraction_rules.xml \
  'path="wcashtestnet-v5/"'
require_text ios/Runner.xcodeproj/project.pbxproj \
  'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
require_text ios/Runner/Runner.entitlements \
  '<key>keychain-access-groups</key>'
require_text macos/Runner/DebugProfile.entitlements \
  '<key>com.apple.security.network.client</key>'
require_text macos/Runner/Release.entitlements \
  '<key>com.apple.security.network.client</key>'
require_text macos/Runner/DebugProfile.entitlements \
  '<key>keychain-access-groups</key>'
require_text macos/Runner/Release.entitlements \
  '<key>keychain-access-groups</key>'
if [[ "$(grep -Fc 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' \
  "$app_dir/ios/Runner.xcodeproj/project.pbxproj")" != 3 ]]; then
  echo 'boundary check failed: iOS keychain entitlement is not wired in every app build configuration' >&2
  exit 1
fi
if [[ "$(grep -Fc 'CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;' \
  "$app_dir/macos/Runner.xcodeproj/project.pbxproj")" != 2 ]] || \
  [[ "$(grep -Fc 'CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;' \
  "$app_dir/macos/Runner.xcodeproj/project.pbxproj")" != 1 ]]; then
  echo 'boundary check failed: macOS keychain entitlements are not wired in every app build configuration' >&2
  exit 1
fi
if grep -Fq 'signingConfigs.getByName("debug")' \
  "$app_dir/android/app/build.gradle.kts"; then
  echo 'boundary check failed: Android release is wired to the debug key' >&2
  exit 1
fi

# Keep the application package deliberately small and stop inherited root-app
# dependencies from entering through a later pubspec edit.
awk '
  /^dependencies:/ { in_dependencies = 1; next }
  /^dev_dependencies:/ { in_dependencies = 0 }
  in_dependencies && /^  [a-zA-Z0-9_]+:/ {
    name = $1; sub(/:$/, "", name); print name
  }
' "$app_dir/pubspec.yaml" | LC_ALL=C sort >"$actual_file"
cat >"$expected_file" <<'EOF'
flutter
flutter_riverpod
flutter_rust_bridge
flutter_secure_storage
go_router
path
path_provider
pretty_qr_code
rust_lib_wcash_warden
EOF
if ! diff -u "$expected_file" "$actual_file"; then
  echo 'boundary check failed: unexpected direct Dart dependency' >&2
  exit 1
fi

awk '
  /^dependencies:/ { in_dependencies = 1; next }
  /^dev_dependencies:/ { in_dependencies = 0 }
  in_dependencies && /^  [a-zA-Z0-9_]+:/ {
    name = $1; sub(/:$/, "", name); print name
  }
' "$app_dir/rust_builder/pubspec.yaml" | LC_ALL=C sort >"$actual_file"
echo flutter >"$expected_file"
if ! diff -u "$expected_file" "$actual_file"; then
  echo 'boundary check failed: unexpected native-builder Dart dependency' >&2
  exit 1
fi

# The native bridge is allowed exactly two direct dependencies. Wolf entries
# below are patches, not linked bridge features.
awk '
  /^\[dependencies\]$/ { in_dependencies = 1; next }
  /^\[/ { in_dependencies = 0 }
  in_dependencies && /^[a-zA-Z0-9_-]+[[:space:]]*=/ {
    name = $1; print name
  }
' "$app_dir/rust/Cargo.toml" | LC_ALL=C sort >"$actual_file"
cat >"$expected_file" <<'EOF'
flutter_rust_bridge
rust_warden
EOF
if ! diff -u "$expected_file" "$actual_file"; then
  echo 'boundary check failed: unexpected direct Rust dependency' >&2
  exit 1
fi

wolf_revision='ea1385c99308e3c00946a3f1cc064a3c3abbf5b0'
for package in pczt zcash_primitives zcash_protocol; do
  require_text rust/Cargo.toml \
    "$package = { git = \"https://github.com/w-cash/wolf.git\", rev = \"$wolf_revision\" }"
done
if [[ "$(grep -Ec '^[a-zA-Z0-9_-]+ = \{ git = "https://github.com/w-cash/wolf.git"' "$app_dir/rust/Cargo.toml")" != 3 ]]; then
  echo 'boundary check failed: unexpected Wolf patch dependency' >&2
  exit 1
fi

cargo tree \
  --manifest-path "$app_dir/rust/Cargo.toml" \
  --locked \
  --depth 1 \
  --edges normal \
  --prefix none >"$tree_file"

if ! grep -Eq '^flutter_rust_bridge v2\.11\.1$' "$tree_file"; then
  echo 'boundary check failed: Rust FRB runtime is not exactly 2.11.1' >&2
  exit 1
fi
if ! grep -Eq '^rust_warden v0\.1\.0 \(/.+/rust_warden\)$' "$tree_file"; then
  echo 'boundary check failed: bridge does not depend on the isolated rust_warden core' >&2
  exit 1
fi
if [[ "$(wc -l <"$tree_file" | tr -d ' ')" != 3 ]]; then
  echo 'boundary check failed: bridge gained an unexpected direct Rust dependency' >&2
  exit 1
fi

# Public native surface: immutable identity, fixed service attestation, and
# Testnet address derivation only.
sed -nE \
  's/^pub (async )?(fn|struct) ([a-zA-Z0-9_]+).*/\2 \3/p' \
  "$app_dir/rust/src/api.rs" | LC_ALL=C sort >"$actual_file"
cat >"$expected_file" <<'EOF'
fn attest_endpoint
fn derive_addresses
fn network_identity
struct WardenAddresses
struct WardenEndpointAttestation
struct WardenNetworkIdentity
EOF
if ! diff -u "$expected_file" "$actual_file"; then
  echo 'boundary check failed: unexpected public Rust bridge API' >&2
  exit 1
fi
require_text rust/src/api.rs 'pub fn network_identity() -> WardenNetworkIdentity'
require_text rust/src/api.rs \
  'pub async fn attest_endpoint() -> Result<WardenEndpointAttestation, String>'
require_text rust/src/api.rs \
  'pub fn derive_addresses(mnemonic: String, account_index: u32) -> Result<WardenAddresses, String>'

find \
  "$app_dir/lib" \
  "$app_dir/android/app" \
  "$app_dir/ios/Runner" \
  "$app_dir/macos/Runner" \
  "$app_dir/linux" \
  "$app_dir/windows" \
  "$app_dir/rust/src" \
  -type f -print0 >"$scan_file"
find "$app_dir/rust_builder" \
  -path "$app_dir/rust_builder/cargokit" -prune -o \
  -path "$app_dir/rust_builder/.dart_tool" -prune -o \
  -type f -print0 >>"$scan_file"

for forbidden in \
  zcash_wallet \
  rust_lib_zcash_wallet \
  com.keplr \
  co.zingo \
  zingo \
  vizor \
  zcash_voting \
  swapkit \
  ZCASH_DEFAULT_NETWORK \
  'zcash:' \
  custom_endpoint \
  customEndpoint \
  endpoint_selector \
  endpointSelector; do
  if xargs -0 grep -FIni "$forbidden" <"$scan_file"; then
    echo "boundary check failed: legacy product surface found: $forbidden" >&2
    exit 1
  fi
done

if xargs -0 grep -EIni \
  '(^|[^[:alnum:]_])(zcash|zec|mainnet|regtest)([^[:alnum:]_]|$)' \
  <"$scan_file"; then
  echo 'boundary check failed: foreign or selectable network surface found' >&2
  exit 1
fi

# Generated Cargokit is vendored separately, but even its local customization
# must use the Warden build override name.
if grep -RIni 'VIZOR_RUST_TOOLCHAIN' "$app_dir/rust_builder/cargokit"; then
  echo 'boundary check failed: inherited build-tool identifier found' >&2
  exit 1
fi
require_text rust_builder/cargokit/build_tool/lib/src/rustup.dart \
  'WARDEN_RUST_TOOLCHAIN'

if find "$app_dir/lib" -type d \( -iname '*swap*' -o -iname '*voting*' \) \
  -print -quit | grep -q .; then
  echo 'boundary check failed: forbidden feature directory found' >&2
  exit 1
fi

echo 'Wcash Warden product boundary verified'
