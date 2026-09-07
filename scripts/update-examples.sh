#!/usr/bin/env sh
#-*-mode: Shell-script; coding: utf-8;-*-
# Description: Here just to update nix and cargo deps for all the examples
# mostly for ci.
set "${SETOPTS:--eu}"

root=$(git rev-parse --show-toplevel) || exit 126
cd "$root" || exit 126

find examples -name flake.nix -exec dirname {} \; | sort | while IFS= read -r dir; do
  printf "nix flake update: %s\n" "$dir"
  (cd "$dir" && nix flake update)
done

find examples -name Cargo.toml -exec dirname {} \; | sort | while IFS= read -r dir; do
  printf "cargo update: %s\n" "$dir"
  (cd "$dir" && cargo update)
done
