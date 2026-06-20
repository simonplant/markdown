#!/usr/bin/env bash
# Build markdown-core for the three Apple triples, generate the Swift bindings,
# and assemble apple/MarkdownCore.xcframework (EPIC-UNIFFI, IOS_BUILD_SPEC §2.5/3.3).
#
# Toolchain: Xcode + `rustup target add aarch64-apple-ios aarch64-apple-ios-sim
# aarch64-apple-darwin`. Run from anywhere in the repo.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin)
echo "==> building libmarkdown_core.a (release) for: ${TARGETS[*]}"
for t in "${TARGETS[@]}"; do
  cargo build -p markdown-core --release --target "$t"
done

GEN="$ROOT/apple/.uniffi-gen"
OUT_SWIFT="$ROOT/apple/Packages/MarkdownCoreFFI/Sources/MarkdownCore"
HDR="$ROOT/apple/.headers"
rm -rf "$GEN" "$HDR"; mkdir -p "$GEN" "$HDR" "$OUT_SWIFT"

echo "==> generating Swift bindings (uniffi library mode)"
cargo run -p markdown-core --features uniffi-bin --bin uniffi-bindgen -- \
  generate \
  --library "$ROOT/target/aarch64-apple-darwin/release/libmarkdown_core.a" \
  --language swift \
  --out-dir "$GEN"

# uniffi emits <ns>.swift + <ns>FFI.h + <ns>FFI.modulemap. The .swift goes into
# the SwiftPM target; the header + modulemap go into the xcframework header dir
# (renamed to module.modulemap, which is what -create-xcframework expects).
cp "$GEN"/*.swift "$OUT_SWIFT/"
cp "$GEN"/*.h "$HDR/"
if ls "$GEN"/*.modulemap >/dev/null 2>&1; then
  cp "$GEN"/*.modulemap "$HDR/module.modulemap"
fi

echo "==> assembling MarkdownCore.xcframework (ios + ios-sim + macos)"
rm -rf "$ROOT/apple/MarkdownCore.xcframework"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/libmarkdown_core.a"     -headers "$HDR" \
  -library "$ROOT/target/aarch64-apple-ios-sim/release/libmarkdown_core.a" -headers "$HDR" \
  -library "$ROOT/target/aarch64-apple-darwin/release/libmarkdown_core.a"  -headers "$HDR" \
  -output  "$ROOT/apple/MarkdownCore.xcframework"

echo "==> done: apple/MarkdownCore.xcframework + Swift bindings in $OUT_SWIFT"
