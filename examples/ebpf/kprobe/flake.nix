# eBPF kprobe program that basically just trampolines some given function and
# outputs a log line. Nothing more than a simple way to demonstrate how to
# accomplish the goal.
{
  description = "mitchty/flakelight-rust ebpf example: kprobe program";
  inputs = {
    flakelight.url = "github:nix-community/flakelight";
    flakelight-rust.url = "path:../../..";
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs";
  };
  outputs =
    {
      self,
      flakelight,
      flakelight-rust,
      crane,
      fenix,
      ...
    }:
    let
      built = flakelight ./. (
        { lib, ... }:
        let
          toolchain =
            system:
            fenix.packages.${system}.latest.withComponents [
              "cargo"
              "rustc"
              "rust-src"
            ];
        in
        {
          imports = [ flakelight-rust.flakelightModules.default ];
          inputs.self = self;

          # bpf-linker/aya tooling is Linux-only.
          systems = [
            "x86_64-linux"
            "aarch64-linux"
          ];

          fileset = lib.fileset.unions [
            (lib.fileset.fileFilter (f: f.hasExt "rs" || f.name == "Cargo.toml") ./.)
            (./. + /Cargo.lock)
            ./deny.toml
          ];

          binaries.kprobe = {
            variants.bpfel = {
              target = "bpfel-unknown-none";

              craneLib =
                { pkgs, system, ... }:
                (crane.mkLib pkgs).overrideToolchain (_: toolchain system);

              extraCargoExtraArgs = "-Z build-std=core";

              # `-Z build-std=core` needs crates in the toolchains Cargo.lock.
              overrideCraneArgs =
                {
                  commonArgs,
                  craneLib,
                  system,
                  ...
                }:
                commonArgs
                // {
                  cargoVendorDir = craneLib.vendorMultipleCargoDeps {
                    inherit (craneLib.findCargoFiles commonArgs.src) cargoConfigs;
                    cargoLockList = [
                      (commonArgs.src + "/Cargo.lock")
                      "${toolchain system}/lib/rustlib/src/rust/library/Cargo.lock"
                    ];
                  };
                };

              # nixpkgs `bpf-linker` needs a specific llvm version to build
              # against. Otherwise you get random segfaults here.
              nativeBuildInputs =
                { pkgs, system, ... }:
                let
                  llvmMajor = lib.strings.trim (
                    builtins.readFile (
                      pkgs.runCommand "kprobe-toolchain-llvm-version" { } ''
                        ${toolchain system}/bin/rustc -vV | sed -n 's/^LLVM version: \([0-9]*\).*/\1/p' > $out
                      ''
                    )
                  );
                in
                [ (pkgs.bpf-linker.override { llvmPackagesForLinker = pkgs."llvmPackages_${llvmMajor}"; }) ];
            };
          };
        }
      );
    in
    # The flakelight-rust module adds testing always, but this can't run unit
    # tests so strip those out if present. `#![no_main]` means there's no `main`
    # for `cargo nextest`'s test so this won't ever work anyway.
    built
    // {
      checks = builtins.mapAttrs (
        _system: checks: builtins.removeAttrs checks [ "kprobe-nextest" ]
      ) built.checks;
    };
}
