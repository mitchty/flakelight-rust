#!/usr/bin/env sh
#-*-mode: Shell-script; coding: utf-8;-*-
# Description: Here for something else to run in ci to validate all of the
# examples build as-is.
#
# Checks every example with no args, if args are given, then that is expected to
# be the example names to check instead of all. If the inputs aren't a valid
# examples it just warns at the end to say: those don't exist thats a you
# problem.
#
# Each example is evaluated with import from derivation disabled, then
# checked to make sure I don't introduce another IFD in the nix library.
# Examples in SKIP_IFD_CHECK, for now only ebpf, are exempt from that check.
#
# Has to be in apps for sandboxing reasons, future mitch don't try getting this
# to work in the sandbox... again. There be many dragons, this is just simpler
# though it sadly doesn't work with nix flake check but whatever.
set "${SETOPTS:--eu}"

root=$(git rev-parse --show-toplevel) || exit 126
cd "$root" || exit 126

tmp_dir=$(mktemp -d) || exit 126
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

list_file="$tmp_dir/list"
missing_file="$tmp_dir/missing"
: > "$missing_file"

find examples -mindepth 2 -maxdepth 2 -name flake.nix | sort > "$list_file"

# Examples exempt from the no import from derivation evaluation check, space
# separated. ebpf's kprobe flake needs IFD on purpose as it reads files out of
# the fenix toolchain derivation directly so it can never pass without IFD, and
# the check also needs toolchains built which fails on macos. SKIP_IFD_CHECK=""
# exempts nothing and lets it all fail even if its not really a failure.
skip_ifd_check="${SKIP_IFD_CHECK-ebpf}"

if [ "$#" -gt 0 ]; then
  filtered_file="$tmp_dir/filtered"
  : > "$filtered_file"
  for example in "$@"; do
    flake="examples/$example/flake.nix"
    if [ -f "$flake" ]; then
      printf '%s\n' "$flake" >> "$filtered_file"
    else
      printf '%s\n' "$example" >> "$missing_file"
    fi
  done
  mv "$filtered_file" "$list_file"
fi

failed=""
while IFS= read -r flake; do
  example=$(basename "$(dirname "$flake")")
  dir="examples/$example"

  printf "checking: %s\n" "$example"
  # Evaluation of the flake should not need to build anything at eval time. IFD
  # makes `nix flake show/check` fail for any nix config without it, so evaluate
  # every system with it off first to catch it being reintroduced accidentally
  # again.
  case " $skip_ifd_check " in
    *" $example "*)
      printf "skip: %s import from derivation check\n" "$example" >&2
      ;;
    *)
      if ! (cd "$dir" && nix flake check --no-build --all-systems --option allow-import-from-derivation false); then
        printf "fatal: %s needs import from derivation to evaluate\n" "$example" >&2
        failed="$failed $example"
        continue
      fi
      ;;
  esac

  if (cd "$dir" && nix flake check -L); then
    printf "ok: %s\n" "$example" >&2
  else
    printf "fatal: %s failed to check\n" "$example" >&2
    failed="$failed $example"
  fi
done < "$list_file"

while IFS= read -r example; do
  printf "warn: example %s wasn't found and was ignored\n" "$example" >&2
done < "$missing_file"

if [ -n "$failed" ]; then
  printf "total failures: %s\n" "$failed" >&2
  exit 1
fi
