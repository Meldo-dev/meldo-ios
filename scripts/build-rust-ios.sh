#!/usr/bin/env bash
# Builds the Rust core for iOS and produces the MeldeCore Swift package inputs:
#   MeldeCore/Generated/MeldeFFI.xcframework
#   MeldeCore/Sources/MeldeCore/melde_ffi.swift
# from the Rust workspace in core/ (the meldo-core git submodule).
#
# macOS only (needs Xcode's toolchain). Runs in CI; on Windows use `cargo test` instead.
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: building the iOS XCFramework requires macOS with Xcode." >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
core="$root/core"
if [[ ! -f "$core/Cargo.toml" ]]; then
  echo "error: core/ is empty. Run: git submodule update --init" >&2
  exit 1
fi
pkg="$root/MeldeCore"
gen="$pkg/Generated"
profile="${PROFILE:-release}"
cargo_flags=(-p melde-ffi --locked)
[[ "$profile" == "release" ]] && cargo_flags+=(--release)

export IPHONEOS_DEPLOYMENT_TARGET=26.0
targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
rustup target add "${targets[@]}" >/dev/null

cd "$core"
for target in "${targets[@]}"; do
  echo "› cargo build $target ($profile)"
  cargo build "${cargo_flags[@]}" --target "$target"
done

# Host build: library-mode bindgen reads the UniFFI metadata from a dylib.
cargo build "${cargo_flags[@]}"
host_lib="$core/target/$profile/libmelde_ffi.dylib"

rm -rf "$gen"
mkdir -p "$gen/headers" "$gen/sim"
echo "› generating Swift bindings"
cargo run -q -p uniffi-bindgen --locked -- generate \
  --library "$host_lib" --language swift --out-dir "$gen/bindings"

cp "$gen/bindings/melde_ffiFFI.h" "$gen/headers/"
cp "$gen/bindings/melde_ffiFFI.modulemap" "$gen/headers/module.modulemap"
cp "$gen/bindings/melde_ffi.swift" "$pkg/Sources/MeldeCore/melde_ffi.swift"

# One fat library for both simulator architectures (Apple silicon + Intel Macs).
lipo -create \
  "$core/target/aarch64-apple-ios-sim/$profile/libmelde_ffi.a" \
  "$core/target/x86_64-apple-ios/$profile/libmelde_ffi.a" \
  -output "$gen/sim/libmelde_ffi.a"

xcodebuild -create-xcframework \
  -library "$core/target/aarch64-apple-ios/$profile/libmelde_ffi.a" -headers "$gen/headers" \
  -library "$gen/sim/libmelde_ffi.a" -headers "$gen/headers" \
  -output "$gen/MeldeFFI.xcframework"

rm -rf "$gen/bindings" "$gen/sim" "$gen/headers"
echo "✓ $gen/MeldeFFI.xcframework"
