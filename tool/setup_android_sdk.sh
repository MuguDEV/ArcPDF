#!/usr/bin/env bash
# Install only the missing Android SDK packages ArcPDF needs, in one sdkmanager call.
# Usage: source tool/setup_android_sdk.sh   (exports pinned build-tools on PATH)
#        tool/setup_android_sdk.sh          (installs; prints pinned path)
# Env: ANDROID_HOME (or ANDROID_SDK_ROOT), ARCPDF_SKIP_PRECACHE=1 to skip flutter precache.
_arcpdf_sdk_main() {
  local platform="android-36" build_tools="36.0.0" ndk="28.2.13676358"
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk" ]]; then
    echo "ANDROID_HOME is not set" >&2
    return 1
  fi
  export ANDROID_HOME="$sdk"

  # A package counts as installed only when package.xml and key files exist.
  local missing=()
  local p="$sdk/platforms/$platform"
  if [[ ! -f "$p/package.xml" || ! -f "$p/android.jar" ]]; then
    missing+=("platforms;$platform")
  fi
  local b="$sdk/build-tools/$build_tools"
  if [[ ! -f "$b/package.xml" || ! -e "$b/apksigner" || ! -e "$b/zipalign" || ! -e "$b/aapt2" ]]; then
    missing+=("build-tools;$build_tools")
  fi
  local n="$sdk/ndk/$ndk"
  if [[ ! -f "$n/package.xml" || ! -f "$n/source.properties" ]] \
    || ! compgen -G "$n/toolchains/llvm/prebuilt/*/bin/clang" >/dev/null; then
    missing+=("ndk;$ndk")
  fi

  if (( ${#missing[@]} > 0 )); then
    local sdkmanager="${SDKMANAGER:-}"
    if [[ -z "$sdkmanager" ]]; then
      if [[ -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
        sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
      elif command -v sdkmanager >/dev/null 2>&1; then
        sdkmanager="$(command -v sdkmanager)"
      else
        echo "sdkmanager not found; install Android cmdline-tools first" >&2
        return 1
      fi
    fi
    echo "Installing missing SDK packages: ${missing[*]}"
    "$sdkmanager" --sdk_root="$sdk" "${missing[@]}" < <(yes) >/dev/null || return 1
  else
    echo "Android SDK packages already installed"
  fi

  # Pin build-tools; never pick "latest" lexicographically.
  export ARCPDF_BUILD_TOOLS_DIR="$b"
  case ":$PATH:" in
    *":$b:"*) ;;
    *) export PATH="$b:$PATH" ;;
  esac
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$b" >>"$GITHUB_PATH"
  fi
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "ARCPDF_BUILD_TOOLS_DIR=$b" >>"$GITHUB_ENV"
  fi
  echo "build-tools: $b"

  # Skip precache when engine artifacts already exist.
  if [[ -z "${ARCPDF_SKIP_PRECACHE:-}" ]] && command -v flutter >/dev/null 2>&1; then
    local flutter_bin flutter_root
    flutter_bin="$(command -v flutter)"
    flutter_root="$(cd "$(dirname "$(readlink -f "$flutter_bin")")/.." && pwd)"
    local eng="$flutter_root/bin/cache/artifacts/engine"
    if [[ -f "$eng/android-arm64-release/flutter.jar" || -f "$eng/android-arm64-release/artifacts.zip" ]] \
       && [[ -f "$eng/android-arm64/flutter.jar" || -d "$eng/android-arm64" ]]; then
      echo "Flutter engine artifacts present; skipping precache"
    else
      flutter precache --android
    fi
  fi
}

_arcpdf_sdk_main "$@"
_arcpdf_rc=$?
unset -f _arcpdf_sdk_main
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exit "$_arcpdf_rc"
fi
return "$_arcpdf_rc" 2>/dev/null || true
