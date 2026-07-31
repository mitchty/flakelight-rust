# Trying to DRY my WET nix code and yeet out flake-utils out of my life.
#
# Note this is VERY opinionated. So unless you like doing things the "mitchty"
# way be sure you want to follow my lead or not.
{
  lib,
  src,
  config,
  flakelight,
  ...
}:
let
  inherit (builtins) fromTOML pathExists readFile;
  inherit (lib)
    mkDefault
    mkIf
    mkMerge
    mkOption
    ;
  inherit (lib.fileset) fileFilter toSource unions;
  inherit (flakelight.types) fileset;

  hasCargoToml = pathExists (src + /Cargo.toml);

  cargoToml = if hasCargoToml then fromTOML (readFile (src + /Cargo.toml)) else { };
  tomlPackage = cargoToml.package or cargoToml.workspace.package or { };

  # I've been doing more on windows so want to be sure my template works to build
  # windows via crosscompilation on linux by default.
  #
  # This will eventually become an optional arg for flakelight cause I abuse it
  # a lot in my repos and am sick of copy/paste.
  windowsTarget = "x86_64-pc-windows-gnu";
in
{
  options = {
    fileset = mkOption {
      type = fileset;
      default = unions [
        (fileFilter (file: file.hasExt "rs" || file.name == "Cargo.toml") src)
        (src + /Cargo.lock)
      ];
    };
  };

  config = mkMerge [
    (mkIf hasCargoToml {
      # Expose the flake's `craneLib` native `rustToolchain` derivations as pkgs attributes.
      #
      # This lets flakelight pick them up by name in devShell.packages like how
      # accelbreadk/flakelight-rust works with its approach.
      withOverlays = [
        config.inputs.fenix.overlays.default
        (final: prev: {
          rustToolchain = config.inputs.fenix.packages.${prev.system}.stable.withComponents [
            "cargo"
            "clippy"
            "llvm-tools"
            "rustc"
            "rust-src"
            "rustfmt"
          ];
          craneLib = (config.inputs.crane.mkLib prev).overrideToolchain (_: final.rustToolchain);
        })
      ];

      description = mkIf (tomlPackage ? description) tomlPackage.description;
      license = mkIf (tomlPackage ? license) (mkDefault tomlPackage.license);
      pname = tomlPackage.name or (mkDefault "cargo-workspace");

      # Default native derivation, with dependency-only artifacts split out into
      # `cargoArtifacts` so that rebuilding your the crates code doesn't require
      # rebuilding every cargo dep needlessly/incessantly.
      package =
        { craneLib, defaultMeta }:
        let
          commonArgs = {
            src = toSource {
              root = src;
              inherit (config) fileset;
            };
            strictDeps = true;
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            meta = defaultMeta;
          }
        );

      checks =
        { craneLib, ... }:
        let
          commonArgs = {
            src = toSource {
              root = src;
              inherit (config) fileset;
            };
            strictDeps = true;
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          "${config.pname}-clippy" = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          "${config.pname}-doc" = craneLib.cargoDoc (
            commonArgs
            // {
              inherit cargoArtifacts;
              env.RUSTDOCFLAGS = "--deny warnings";
            }
          );

          "${config.pname}-nextest" = craneLib.cargoNextest (
            commonArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            }
          );

          # Setup cargo-deny so that licenses, bans, and source urls are validated.
          #
          # The advisory-db check uses network access, I'll figure out how to
          # point it at the input advisory-db later so fully offline works as
          # expected.
          "${config.pname}-deny" = craneLib.cargoDeny { inherit (commonArgs) src; };
        };

      # Windows cross build using x86_64-pc-windows-gnu. Linux only its doesn't
      # work on darwin. Haven't tested if this works on linux arm don't care
      # much. Might make it possible to build a windows arm binary too at some
      # point. I have no need for such things so not adding it.
      packages =
        { system, ... }:
        {
          # Hacky way to abuse cargo-deny's graph output to generate graphviz
          # dot files (then render them to pngs) for any duplicate/banned
          # dependencies. Pin a specific cargo-deny version since the `-g`
          # graph-output flag isn't guaranteed to exist/behave the same
          # across versions. Pair with `apps.dotdeps` (nix run .#dotdeps) to
          # open the resulting pngs, if any were generated.
          dotdeps =
            {
              pkgs,
              craneLib,
              defaultMeta,
              ...
            }:
            let
              cargo-deny-0_19 = pkgs.rustPlatform.buildRustPackage rec {
                pname = "cargo-deny";
                version = "0.19.9";

                src = pkgs.fetchFromGitHub {
                  owner = "EmbarkStudios";
                  repo = "cargo-deny";
                  rev = version;
                  hash = "sha256-b3p4UxMDUNMKusgGDji3A0myfAfYU+o4DFnhM4mrWao=";
                };

                cargoHash = "sha256-+FWEA2T8CASg3MmTb7WpN4MO8lwiLZtsVDuWMddkUgA=";

                nativeBuildInputs = [ pkgs.pkg-config ];
                buildInputs = [
                  pkgs.zstd
                ]
                ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.apple-sdk ];

                env.ZSTD_SYS_USE_PKG_CONFIG = true;

                # Tests require network access.
                doCheck = false;

                meta = defaultMeta // {
                  description = "Cargo plugin to help you manage large dependency graphs";
                  mainProgram = "cargo-deny";
                };
              };
            in
            craneLib.mkCargoDerivation {
              src = toSource {
                root = src;
                inherit (config) fileset;
              };
              pname = "dotdeps";

              nativeBuildInputs = [
                pkgs.graphviz
                cargo-deny-0_19
              ];

              # crane requires cargoArtifacts but like cargoDeny set this to null.
              cargoArtifacts = null;
              doInstallCargoArtifacts = false;

              # Note: if there are any bans/dups etc... we let things go, this
              # is intended to generate graphviz dot files, not fail the build.
              buildPhaseCargoCommand = ''
                mkdir -p "$out"
                cargo --offline deny check -g "$out" bans || true
              '';

              installPhaseCommand = ''
                for f in "$out"/graph_output/*.dot; do
                  [ -e "$f" ] || continue
                  dot -Tpng "$f" -o "$out/graph_output/$(basename "''${f%.dot}").png"
                done
              '';
            };
        }
        # TODO: hacky can prolly use nixpkgs lib for this.
        // lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
          windows =
            { defaultMeta, ... }:
            let
              pkgsWindows = import config.inputs.nixpkgs {
                inherit system;
                crossSystem = {
                  config = "x86_64-w64-mingw32";
                  libc = "msvcrt";
                };
              };
              toolchain = config.inputs.fenix.packages.${system}.combine [
                config.inputs.fenix.packages.${system}.stable.cargo
                config.inputs.fenix.packages.${system}.stable.rustc
                config.inputs.fenix.packages.${system}.targets.${windowsTarget}.stable.rust-std
              ];
              craneLibWindows = (config.inputs.crane.mkLib pkgsWindows).overrideToolchain (_: toolchain);
              commonArgsWindows = {
                src = toSource {
                  root = src;
                  inherit (config) fileset;
                };
                strictDeps = true;
                # Can't run windows binaries during the linux build without
                # binfmt setup by default so lets not do it. Testing of windows
                # binaries can be done via wine methinks.
                doCheck = false;
                CARGO_BUILD_TARGET = windowsTarget;
                nativeBuildInputs = with pkgsWindows.buildPackages; [
                  nasm
                  cmake
                ];
                buildInputs = [ pkgsWindows.windows.pthreads ];
                # TODO: Extra CFLAGS/CC_... setup if something like aws-lc-sys
                # gets pulled in. I had this in mitchty.github.io but will add
                # it back if/when I need it again. I can't remember if I do...
              };
              cargoArtifacts = craneLibWindows.buildDepsOnly commonArgsWindows;
            in
            (craneLibWindows.buildPackage (
              commonArgsWindows
              // {
                inherit cargoArtifacts;
                meta = defaultMeta // {
                  platforms = [ "x86_64-windows" ];
                };
              }
            )).overrideAttrs
              (old: {
                meta = (old.meta or { }) // {
                  platforms = [ "x86_64-windows" ];
                };
              });
        };

      # Note for now this is a batteries included setup. That means profiling
      # targets work with all that bs too for abusage as needed. I end up
      # tracking down memory resource leaks a lot from rando crates.
      devShell = {
        packages =
          pkgs: with pkgs; [
            rustToolchain
            rust-analyzer
            cargo-edit
            cargo-outdated
            cargo-nextest
            cargo-deny
            cargo-bloat
            # For `jeprof` call graphs using jemalloc-pprof-style profiling dumps
            ghostscript
          ];

        env = { rustPlatform, ... }: { RUST_SRC_PATH = "${rustPlatform.rustLibSrc}"; };
      };

      perSystem = pkgs: {
        checks.git-hooks = config.inputs.git-hooks.lib.${pkgs.system}.run {
          inherit src;
          hooks = {
            convco.enable = true;

            nix-flake-check = {
              enable = true;
              name = "nix flake check";
              entry = "nix flake check -L";
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
      };

      # `nix run .#update` bumps flake inputs for the module.
      apps.update =
        { pkgs, ... }:
        {
          type = "app";
          program = "${
            pkgs.writeShellApplication {
              name = "update";
              text = ''
                ${pkgs.nix}/bin/nix flake update
              '';
            }
          }/bin/update";
        };

      # Opens the cargo-deny duplicate-dep graphs output in a browser/viewer if
      # any were generated, otherwise says so and no-ops.
      apps.dotdeps =
        {
          pkgs,
          system,
          ...
        }:
        let
          opener = if pkgs.stdenv.isDarwin then "open" else "xdg-open";
        in
        {
          type = "app";
          program = "${
            pkgs.writeShellApplication {
              name = "dotdeps";
              text = ''
                dir="${config.inputs.self.packages.${system}.dotdeps}/graph_output"
                if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
                  echo "no duplicate cargo deps found in $dir, nothing to do."
                else
                  ${opener} "$dir"
                fi
              '';
            }
          }/bin/dotdeps";
        };
    })
  ];
}
