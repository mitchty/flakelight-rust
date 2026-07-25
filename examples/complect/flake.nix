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
    flakelight-treefmt = {
      url = "github:m15a/flakelight-treefmt";
      inputs.flakelight.follows = "flakelight";
    };
  };
  outputs =
    {
      self,
      flakelight,
      flakelight-rust,
      flakelight-treefmt,
      ...
    }:
    flakelight ./. (
      { lib, ... }:
      {
        imports = [
          flakelight-rust.flakelightModules.default
          flakelight-treefmt.flakelightModules.default
        ];
        inputs.self = self;

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        fileset = lib.fileset.unions [
          (lib.fileset.fileFilter (f: f.hasExt "rs" || f.name == "Cargo.toml") ./.)
          (./. + /Cargo.lock)
          ./deny.toml
        ];

        # How to enable formatting too, not provided by the flakelight module
        # intentionally maybe someday?
        treefmtConfig = {
          programs.nixfmt.enable = true;
          programs.deadnix.enable = true;
          programs.statix.enable = true;
          programs.taplo.enable = true;

          settings.global.excludes = [
            "*/flake.lock"
          ];
        };

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

          # `engine` needs both `common` and `extra` crates and demonstrates plain
          # cargo profile variants plus a CUDA build using custom `pkgs` attr set
          # with cudaSupport enabled, restricted to Linux via `systems`.
          engine = {
            crate = ./crates/engine;
            pathDeps = [
              ./crates/common
              ./crates/extra
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
        };
      }
    );
}
