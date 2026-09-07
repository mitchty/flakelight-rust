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

# Handle updating wasm-bindgen-cli for any example that may be using it. This is
# hacky-af but can't do it work directly in the sub example flake due to
# ../../etc...
failed=""
list_file=$(mktemp)
find examples -type f -path '*/nix/packages/wasm-bindgen-cli.nix' | sort > "$list_file"

while IFS= read -r pkg_file; do
  example_dir=$(dirname "$(dirname "$(dirname "$pkg_file")")")
  manifest="$example_dir/Cargo.toml"
  [ -f "$manifest" ] || continue

  resolved=$(cargo pkgid -p wasm-bindgen --manifest-path "$manifest" 2> /dev/null | sed 's/.*@//') || continue
  [ -n "$resolved" ] || continue

  printf "reconciling wasm-bindgen-cli version update %s in %s\n" "$resolved" "$pkg_file"

  scratch=$(mktemp -d)
  cp "$pkg_file" "$scratch/wasm-bindgen-cli.nix"
  cat > "$scratch/flake.nix" << 'EOF'
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: {
        wasm-bindgen-cli = (import nixpkgs { inherit system; }).callPackage ./wasm-bindgen-cli.nix { };
      });
    };
}
EOF

  if (cd "$scratch" && nix-update wasm-bindgen-cli --flake --version "$resolved"); then
    cp "$scratch/wasm-bindgen-cli.nix" "$pkg_file"
  else
    printf "fatal: failed to reconcile wasm-bindgen-cli in %s\n" "$pkg_file" >&2
    failed="$failed $pkg_file"
  fi
  rm -rf "$scratch"
done < "$list_file"
rm -f "$list_file"

if [ -n "$failed" ]; then
  printf "wasm-bindgen-cli version reconciliation failures: %s\n" "$failed" >&2
  exit 1
fi
