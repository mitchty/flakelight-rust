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
