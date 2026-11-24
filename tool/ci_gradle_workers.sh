#!/usr/bin/env bash
# Select Gradle worker count from CPU cores and RAM and write it to
# $GRADLE_USER_HOME/gradle.properties, keeping all other keys untouched.
#
#   RAM < 8 GB   -> 2 workers
#   RAM 8-16 GB  -> 4 workers
#   RAM > 16 GB  -> up to 8 workers
#   always limited by CPU cores, minimum 1
#
# Test overrides: ARCPDF_TEST_MEM_GB, ARCPDF_TEST_CPUS.
# Use --print to only print the selected worker count.
set -euo pipefail

detect_mem_gb() {
  if [[ -n "${ARCPDF_TEST_MEM_GB:-}" ]]; then
    echo "$ARCPDF_TEST_MEM_GB"
  elif [[ -r /proc/meminfo ]]; then
    awk '/^MemTotal:/ { printf "%d", $2 / 1048576 }' /proc/meminfo
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.memsize | awk '{ printf "%d", $1 / 1073741824 }'
  else
    echo 4
  fi
}

detect_cpus() {
  if [[ -n "${ARCPDF_TEST_CPUS:-}" ]]; then
    echo "$ARCPDF_TEST_CPUS"
  elif command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    echo 2
  fi
}

select_workers() {
  local mem="$1" cpus="$2" workers
  if (( mem < 8 )); then
    workers=2
  elif (( mem <= 16 )); then
    workers=4
  else
    workers=8
  fi
  (( workers > cpus )) && workers=$cpus
  (( workers < 1 )) && workers=1
  echo "$workers"
}

mem_gb="$(detect_mem_gb)"
cpus="$(detect_cpus)"
workers="$(select_workers "$mem_gb" "$cpus")"

if [[ "${1:-}" == "--print" ]]; then
  echo "$workers"
  exit 0
fi

gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
props="$gradle_home/gradle.properties"
mkdir -p "$gradle_home"
touch "$props"

# Cargo jobs share the CPU with Gradle workers, so keep them at half the workers.
cargo_jobs=$(( workers / 2 ))
(( cargo_jobs < 1 )) && cargo_jobs=1

tmp="$(mktemp)"
grep -v -E '^org\.gradle\.workers\.max=' "$props" >"$tmp" || true
{
  echo "org.gradle.workers.max=$workers"
} >>"$tmp"
cat "$tmp" >"$props"
rm -f "$tmp"

if [[ -n "${GITHUB_ENV:-}" && -z "${ARCPDF_CARGO_JOBS:-}" ]]; then
  echo "ARCPDF_CARGO_JOBS=$cargo_jobs" >>"$GITHUB_ENV"
fi

echo "mem=${mem_gb}GB cpus=$cpus org.gradle.workers.max=$workers cargo_jobs=$cargo_jobs ($props)"
