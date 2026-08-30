# Complect example trying to abuse all of the nonsense this bucket of functions allows.
#
# Crap like different binaries with different `pathDeps`, subsets of the shared
# crates, a Windows cross target, a wasm32 target with provided caller-supplied
# `wasm-bindgen-cli` pinned pkd derivation, a CUDA variant using a fully custom
# `pkgs` set, a static/portable variant, and plain cargo-profile variants.
#
# Note for ci reasons and to force downstream users to be explicit about
# their own nix dependencies, there is no flake.lock file provided for the
# example itself.
#
# Note the `engine.cuda` variant is Linux-only and is excluded from ci runs
# since building `cudaPackages` from source on a resource-constrained hosted
# runner isn't realistic for github runners.
#
# `scripts/test-examples.sh` can still run it though for anyone testing locally
# or on a beefier self-hosted runner of doooooom.
{
  description = "mitchty/flakelight-rust complect aka kitchen-sink example";
  inputs = {
    flakelight.url = "github:nix-community/flakelight";
    flakelight-rust.url = "path:../..";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
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
      rust-overlay,
      ...
    }:
    flakelight ./. (
      { lib, ... }:
      let
        # Build an app for flashing a variant based on the firmeware build
        # derivation name. aka `flash-${name}-${variant}` that way you could
        # conceivably build multiple firmware targets and flash them separately
        # to different boards. This example is complect enough as it is so this
        # is "for show, like a pony". You know your needs I don't.
        mkFlashApp =
          name: variant:
          { pkgs, ... }:
          {
            type = "app";
            program = "${
              pkgs.writeShellApplication {
                name = "flash-${name}-${variant}";
                runtimeInputs = [ pkgs.espflash ];
                text = ''
                  espflash flash --monitor "$@" "${pkgs."${name}-${variant}"}/bin/${name}"
                '';
              }
            }/bin/flash-${name}-${variant}";
          };
      in
      {
        imports = [ flakelight-rust.flakelightModules.default ];
        inputs.self = self;

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        withOverlays = [ rust-overlay.overlays.default ];

        fileset = lib.fileset.unions [
          (lib.fileset.fileFilter (f: f.hasExt "rs" || f.name == "Cargo.toml") ./.)
          (./. + /Cargo.lock)
          ./deny.toml
        ];

        binaries = {
          # `agent` only needs `common` crate not the whole workspace.
          agent = {
            crate = ./crates/agent;
            pathDeps = [ ./crates/common ];

            variants = {
              default = { };

              windows = {
                target = "x86_64-pc-windows-gnu";

                systems = [
                  "x86_64-linux"
                  "aarch64-linux"
                ];
              };

              # `nix build .#agent-portable`: fully static musl on Linux, or
              # a system-library-only-linked build on macOS.
              portable = {
                portable = true;
              };

              wasm = {
                target = "wasm32-unknown-unknown";
                extraCargoExtraArgs = "--features wasm";
                cargoProfile = "release-small";

                wasm = {
                  enable = true;
                  # Caller-pinned wasm-bindgen-cli goes here as, this module
                  # never ships one as its version must track whatever the
                  # crate's own `wasm-bindgen` dependency needs anyway so there
                  # is no real point to.
                  bindgenCli =
                    { pkgs, lib }:
                    pkgs.rustPlatform.buildRustPackage rec {
                      pname = "wasm-bindgen-cli";
                      version = "0.2.122";

                      src = pkgs.fetchCrate {
                        inherit pname version;
                        hash = "sha256-vO4RSxi/sMWxmsEs3GuljdMfIRSu75A+Q+c5wgYToRU=";
                      };
                      cargoHash = "sha256-Inup6vvJSG5ghNyeDPyZbfZo4d0LsMG2OJfStoaeDBs=";

                      nativeBuildInputs = [ pkgs.pkg-config ];
                      buildInputs = [
                        pkgs.openssl
                      ]
                      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.apple-sdk ];

                      checkFlags = [ "--skip=reference::tests::works" ];

                      meta = {
                        description = "CLI tool for wasm-bindgen";
                        mainProgram = "wasm-bindgen";
                      };
                    };
                };
              };
            };
          };

          # This target derivation is here just to demonstrate you can even yeet
          # in third party .a deps from in this case c into a fully static
          # binary on linux and macos without dynamic linking.
          #
          # In this case its "just" the aws-lc-sys crypto crate dep. Pretty ezpz tbh.
          #
          # I can add more crazy later, but the default checks on the portable
          # binary ensure there aren't any DYNAMIC or INTERP segments in the ELF
          # binary or equivalent links on macos after build so this example
          # working means its all good in the woods.
          dep = {
            crate = ./crates/dep;
            pathDeps = [ ./crates/common ];

            nativeBuildInputs =
              { pkgs, lib, ... }:
              [
                pkgs.cmake
                pkgs.perl
              ]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ pkgs.nasm ];

            variants = {
              default = { };

              portable = {
                portable = true;
              };
            };
          };

          # `engine` needs both `common` and `extra` crates and demonstrates
          # cargo profile variants plus a CUDA build using a customized `pkgs`
          # attr set with cudaSupport enabled, restricted to Linux via
          # `systems`.
          engine = {
            crate = ./crates/engine;
            pathDeps = [
              ./crates/common
              ./crates/extra
              ./crates/nostdlib
            ];

            variants = {
              default = { };

              release = {
                cargoProfile = "release";
                rustflags = "-D warnings";
              };

              release-fast = {
                cargoProfile = "release-fast";
              };

              cuda = {
                systems = [
                  "x86_64-linux"
                  "aarch64-linux"
                ];
                extraCargoExtraArgs = "--features cuda";
                cargoProfile = "release";

                # Swap pkg set out for a cuda enabled pkg set.
                pkgs =
                  { pkgs, system, ... }:
                  import pkgs.path {
                    inherit system;
                    config = {
                      allowUnfree = true;
                      cudaSupport = true;
                    };
                  };

                nativeBuildInputs = { pkgs, ... }: [ pkgs.autoAddDriverRunpath ];

                buildInputs =
                  { pkgs, ... }:
                  with pkgs.cudaPackages;
                  [
                    cuda_cudart
                    cuda_nvcc
                    cuda_nvrtc
                    cccl
                    libcublas
                  ];

                env = { pkgs, ... }: { CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}"; };
              };
            };
          };

          # `firmware` is a #![no_std] RISC-V ESP32 binary sharing the
          # `nostdlib` crate with `engine` - see the `esp32c3` variant's
          # `craneLib` for how the non-fenix nightly toolchain gets swapped
          # in.
          firmware = {
            crate = ./crates/firmware;
            pathDeps = [ ./crates/nostdlib ];

            nativeBuildInputs = { pkgs, ... }: [ pkgs.espflash ];

            variants = {
              esp32c3 = {
                target = "riscv32imc-unknown-none-elf";

                # Keep in sync with crates/firmware/.cargo/config.toml's
                # rustflags, this is the nix-build-time copy of the same
                # portable-atomic/esp-hal single-core-atomics workaround.
                #
                # Do NOT add `-C target-feature=+a`: that tells
                # portable-atomic the target has real atomics, which makes
                # it reject `portable_atomic_unsafe_assume_single_core` as
                # inapplicable and hard error instead. beepbeepimmajeep's
                # working flake.nix never sets it for this exact reason.
                rustflags = lib.concatStringsSep " " [
                  "--cfg portable_atomic_unsafe_assume_single_core"
                  "-C link-arg=-Tlinkall.x"
                  "-C linker=rust-lld"
                ];

                craneLib =
                  { pkgs, target, ... }:
                  let
                    toolchain = pkgs.rust-bin.nightly.latest.default.override {
                      targets = [ target ];
                      extensions = [ "rust-src" ];
                    };
                  in
                  (crane.mkLib pkgs).overrideToolchain (_: toolchain);
              };
            };
          };
        };

        apps."flash-firmware-esp32c3" = mkFlashApp "firmware" "esp32c3";
      }
    );
}
