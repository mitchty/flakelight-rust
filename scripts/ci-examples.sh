#!/usr/bin/env sh
#-*-mode: Shell-script; coding: utf-8;-*-
# Description: Here for something else to run in ci to validate all of the
# examples build as-is.
#
# Has to be in apps for sandboxing reasons.
set "${SETOPTS:--eu}"

root=$(git rev-parse --show-toplevel) || exit 126
cd "$root" || exit 126

failed=""
list_file=$(mktemp)
find examples -mindepth 2 -maxdepth 2 -name flake.nix | sort > "$list_file"

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
rm -f "$list_file"

if [ -n "$failed" ]; then
  printf "total failures: %s\n" "$failed" >&2
  exit 1
fi
