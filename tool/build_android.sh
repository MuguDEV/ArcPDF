#!/usr/bin/env bash
# Build ArcPDF APKs.
# Usage: tool/build_android.sh <debug|preview|preview-compressed|full> [extra flutter args]
#   debug              arm64-v8a debug APK
#   preview            arm64-v8a release APK, split per ABI, obfuscated
#   preview-compressed preview with ARCPDF_COMPRESS_NATIVE_LIBS=true
#   full               all ABIs, release flags as preview
# flutter pub get runs only when pubspec.yaml or pubspec.lock changed since the
# last successful resolution (hash stored in .arc-build). flutter clean is never run.
set -euo pipefail

mode="${1:-}"
if [[ -z "$mode" ]]; then
  echo "usage: $0 <debug|preview|preview-compressed|full> [flutter args]" >&2
  exit 2
fi
shift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

state_dir="$repo_root/.arc-build"
hash_file="$state_dir/pubspec.hash"
mkdir -p "$state_dir"

hash_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

current_hash() {
  local f
  for f in pubspec.yaml pubspec.lock; do
    [[ -f "$f" ]] && hash_cmd "$f" | awk '{print $1}' || echo missing
  done | tr '\n' ' '
}

want="$(current_hash)"
have=""
[[ -f "$hash_file" ]] && have="$(cat "$hash_file")"

pub_flag=()
if [[ "$want" != "$have" || ! -f .dart_tool/package_config.json ]]; then
  echo "pubspec changed or not resolved: running flutter pub get"
  flutter pub get
  printf '%s' "$want" >"$hash_file"
fi
# Resolution succeeded (or was already current), so skip implicit pub get.
pub_flag=(--no-pub)

release_flags=(--release --target-platform android-arm64 --split-per-abi
  --obfuscate --split-debug-info=build/symbols/preview)

case "$mode" in
  debug)
    ARCPDF_ABIS=arm64-v8a flutter build apk --debug --target-platform android-arm64 "${pub_flag[@]}" "$@"
    ;;
  preview)
    ARCPDF_ABIS=arm64-v8a flutter build apk "${release_flags[@]}" "${pub_flag[@]}" "$@"
    ;;
  preview-compressed)
    ARCPDF_ABIS=arm64-v8a ARCPDF_COMPRESS_NATIVE_LIBS=true \
      flutter build apk "${release_flags[@]}" "${pub_flag[@]}" "$@"
    ;;
  full)
    ARCPDF_ABIS="${ARCPDF_ABIS:-arm64-v8a,armeabi-v7a,x86_64}" \
      flutter build apk --release --target-platform android-arm,android-arm64,android-x64 \
      --split-per-abi --obfuscate --split-debug-info=build/symbols/full "${pub_flag[@]}" "$@"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
