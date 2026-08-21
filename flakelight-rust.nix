# Trying to DRY my WET nix code and yeet flake-utils out of my life.
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

  # TODO: arm windows? I got no way to test it anyway so future mitch problem
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

    # Here for cross compilation for windows for matching target variants. Other
    # targets just get the same fenix rust-std target added to the native
    # toolchain.
    crossSystems = mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {
        "x86_64-pc-windows-gnu" = {
          config = "x86_64-w64-mingw32";
          libc = "msvcrt";
        };
      };
    };

    cargoDenyPackage = mkOption {
      type = lib.types.functionTo lib.types.package;
      default = { pkgs, ... }: pkgs.cargo-deny-0_19;
      description = "Cargo deny package derivation";
    };

    # Way to splice in other binary crate derivations. Each entry produces a
    # package derivation per defined variant.
    binaries = mkOption {
      default = { };
      description = "Additional cargo binaries to build, with one or more build `variant` types.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              crate = mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = ''
                  Path to the rust crate binary source directory. Use with `pathDeps` to autocompute a fileset covering the binary and the workspace crates it specifically needs, instead of the entire workspace. Default of `null` uses the whole workspace `fileset`.
                '';
              };

              pathDeps = mkOption {
                type = lib.types.listOf lib.types.path;
                default = [ ];
                description = "Extra workspace crate directories this target depends on.";
              };

              fileset = mkOption {
                type = lib.types.nullOr fileset;
                default = null;
                description = "Explicit fileset to override the default `crate`/`pathDeps` setup if given";
              };

              cargoExtraArgs = mkOption {
                type = lib.types.str;
                default = "-p ${name}";
                description = "Extra `cargo` args for this target. Variants append to this prefix with `extraCargoExtraArgs`.";
              };

              nativeBuildInputs = mkOption {
                type = lib.types.functionTo (lib.types.listOf lib.types.package);
                default = _: [ ];
                description = "Extra native build package derivations to use for all variants.";
              };

              buildInputs = mkOption {
                type = lib.types.functionTo (lib.types.listOf lib.types.package);
                default = _: [ ];
                description = "Extra build package derivations to use for all variants.";
              };

              env = mkOption {
                type = lib.types.functionTo lib.types.attrs;
                default = _: { };
                description = ''
                  Extra env vars to apply to all variants.
                '';
              };

              overrideCraneArgs = mkOption {
                type = lib.types.functionTo lib.types.attrs;
                default = { commonArgs, ... }: commonArgs;
                description = ''
                  Escape hatch function to help return the final crane `commonArgs`. Can be overriden per-variant. Allows changing args directly if needed.
                '';
              };

              extraCraneArgs = mkOption {
                type = lib.types.functionTo lib.types.attrs;
                default = _: { };
                description = ''
                  Extra crane args merged via `//` on top of the final `commonArgs`, after `overrideCraneArgs` has run. Behaves more like you'd expect a nix Arg attrset.
                '';
              };

              postProcess = mkOption {
                type = lib.types.functionTo lib.types.package;
                default = { package, ... }: package;
                description = ''
                  Terminal function applied at the end to handle wrapping of things like env vars or asset paths. Can be overridden per-variant.
                '';
              };

              variants = mkOption {
                default = {
                  default = { };
                };
                description = ''
                  Named build variants of this derivation. The `default` variant produces `packages.<name>`, other names produce `packages.NAME-VARIANT`.
                '';
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options = {
                      systems = mkOption {
                        type = lib.types.nullOr (lib.types.listOf lib.types.str);
                        default = null;
                        description = "Restrict variant to specific systems. `null` means all systems.";
                      };

                      target = mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Rust target triple for this variant, or `null` for native.";
                      };

                      pkgs = mkOption {
                        type = lib.types.functionTo lib.types.attrs;
                        default = { pkgs, ... }: pkgs;
                        description = ''
                          Function to return a final package set to build variant with. Here for things like enabling cudaSupport true within the package set. Defaults to identity.
                        '';
                      };

                      cargoProfile = mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Cargo profile name to build with, set via `CARGO_PROFILE` env var.";
                      };

                      rustflags = mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                      };

                      extraCargoExtraArgs = mkOption {
                        type = lib.types.str;
                        default = "";
                        description = "Extra args appended to the parent binary derivations `cargoExtraArgs`, ex: `--features foo/bar` etc.";
                      };

                      env = mkOption {
                        type = lib.types.functionTo lib.types.attrs;
                        default = _: { };
                        description = "Merged over the parent derivations `env`.";
                      };

                      nativeBuildInputs = mkOption {
                        type = lib.types.functionTo (lib.types.listOf lib.types.package);
                        default = _: [ ];
                        description = "Native build inputs appended to the derivations `nativeBuildInputs`.";
                      };

                      buildInputs = mkOption {
                        type = lib.types.functionTo (lib.types.listOf lib.types.package);
                        default = _: [ ];
                        description = "Build inputs appended to the derivations `buildInputs`.";
                      };

                      overrideCraneArgs = mkOption {
                        type = lib.types.nullOr (lib.types.functionTo lib.types.attrs);
                        default = null;
                        description = ''
                          Overrides the parent binary's `overrideCraneArgs` entirely if set, not merged or additive.
                        '';
                      };

                      extraCraneArgs = mkOption {
                        type = lib.types.functionTo lib.types.attrs;
                        default = _: { };
                        description = "Extra additive crane attr args merged via `//` on top of the parent binaries `extraCraneArgs` result, applied after `overrideCraneArgs`.";
                      };

                      postProcess = mkOption {
                        type = lib.types.nullOr (lib.types.functionTo lib.types.package);
                        default = null;
                        description = "Allows user to override the derivations `postProcess` setup.";
                      };

                      portable = mkOption {
                        type = lib.types.bool;
                        default = false;
                        description = ''
                          Only useful if true and when `target == null` aka on a native platform.
                          On Linux sets things up to build a static elf binary via cross compilation for `<hostArch>-unknown-linux-musl` targets with `CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static -C link-arg=-static"`.
                          On macOS, resets `pkgs` with `crossSystem = pkgs.stdenv.hostPlatform` to force system-library-only linking versus /nix/store. Note that if you link libraries in the /nix/store nothing prevents this from not being portable. You break it you buy it, not this guy.

                          Nop with `target` set. Implies `doCheck = false` as tests tend not to cross compile well.
                        '';
                      };

                      wasm = {
                        enable = mkOption {
                          type = lib.types.bool;
                          default = false;
                          description = "Run the variant build through `wasm-bindgen` and optionally `wasm-opt`.";
                        };

                        bindgenCli = mkOption {
                          type = lib.types.functionTo lib.types.package;
                          default =
                            _:
                            throw "flakelight-rust: `binaries.NAME.variants.VARIANT.wasm.bindgenCli` must be provided when `wasm.enable = true`.";
                          description = "Bindgen cli package derivation, required to be provided.";
                        };

                        wasmOptEnable = mkOption {
                          type = lib.types.bool;
                          default = true;
                        };

                        # TODO: probably want to make wasm options to be appendable but this is already gihugic.
                        wasmOptArgs = mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [
                            "-Oz"
                            "--enable-bulk-memory"
                            "--enable-mutable-globals"
                            "--enable-nontrapping-float-to-int"
                            "--enable-sign-ext"
                          ];
                        };
                      };

                      meta = mkOption {
                        type = lib.types.attrs;
                        default = { };
                        description = "Meta attrs merged over the `defaultMeta` derivation for this variant.";
                      };
                    };
                  }
                );
              };
            };
          }
        )
      );
    };
  };

  config = mkMerge [
    (mkIf hasCargoToml {
      # Expose the flake's `craneLib` native `rustToolchain` derivations as nix pkg attributes.
      #
      # This is to allow flakelight to use packages by name directly in say
      # devShell.packages cause lazy.
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
      # rebuilding every cargo dep needlessly/incessantly. Kinda the whole
      # reason for this chungus, I hate rebuilding deps constantly.
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

          # Setup cargo-deny so that licenses, bans, and source urls are
          # validated by default.
          #
          # The advisory-db check uses network access, I'll figure out how to
          # point it at the input advisory-db later so fully offline works as
          # expected, porting this all over from my own stuff is enough for now.
          "${config.pname}-deny" = craneLib.cargoDeny { inherit (commonArgs) src; };
        };

      # Windows cross build using x86_64-pc-windows-gnu. Linux only its doesn't
      # work on darwin. Haven't tested if this works on linux arm don't care
      # much. Might make it possible to build a windows arm binary too at some
      # point. I have no need for such things so not adding it unless I do need it.
      packages =
        { system, ... }:
        let
          mkCrossPkgsFor =
            target:
            import config.inputs.nixpkgs {
              inherit system;
              crossSystem = config.crossSystems.${target};
            };

          mkCraneLibFor =
            target: pkgsFor:
            let
              toolchain =
                if target == null then
                  config.inputs.fenix.packages.${system}.stable.toolchain
                else
                  config.inputs.fenix.packages.${system}.combine [
                    config.inputs.fenix.packages.${system}.stable.cargo
                    config.inputs.fenix.packages.${system}.stable.rustc
                    config.inputs.fenix.packages.${system}.targets.${target}.stable.rust-std
                  ];
            in
            (config.inputs.crane.mkLib pkgsFor).overrideToolchain (_: toolchain);

          depsSrc = toSource {
            root = src;
            fileset = unions [
              (src + /Cargo.toml)
              (src + /Cargo.lock)
              (fileFilter (file: file.name == "Cargo.toml" || file.name == "build.rs") src)
            ];
          };

          mkCrateSrc =
            pkgs: craneLib: binName: binCfg:
            if binCfg.fileset != null then
              toSource {
                root = src;
                inherit (binCfg) fileset;
              }
            else if binCfg.crate != null then
              let
                dummyWorkspaceSrc = craneLib.mkDummySrc { inherit src; };
                dirs = [ binCfg.crate ] ++ binCfg.pathDeps;
                realSrc = toSource {
                  root = src;
                  fileset = unions (
                    [
                      (src + /Cargo.toml)
                      (src + /Cargo.lock)
                    ]
                    ++ map craneLib.fileset.commonCargoSources dirs
                  );
                };
              in
              pkgs.runCommand "${binName}-src" { } ''
                mkdir -p $out
                cp --recursive --no-preserve=mode,ownership ${dummyWorkspaceSrc}/. $out/
                chmod -R u+w $out
                cp --recursive --no-preserve=mode,ownership ${realSrc}/. $out/
                chmod -R u+w $out
              ''
            else
              toSource {
                root = src;
                inherit (config) fileset;
              };

          mkWasmOutput =
            {
              pkgs,
              lib,
              wasmCfg,
              wasmPackage,
              wasmFile,
              pname,
            }:
            let
              bindgenCli = wasmCfg.bindgenCli { inherit pkgs lib; };
            in
            pkgs.runCommand "${pname}-wasm-bindgen"
              {
                nativeBuildInputs = [ bindgenCli ] ++ lib.optionals wasmCfg.wasmOptEnable [ pkgs.binaryen ];
              }
              (
                ''
                  mkdir -p $out/wasm
                  ${bindgenCli}/bin/wasm-bindgen \
                    --out-dir $out/wasm \
                    --target web \
                    --no-typescript \
                    ${wasmPackage}/${wasmFile}
                ''
                + lib.optionalString wasmCfg.wasmOptEnable ''
                  for f in $out/wasm/*_bg.wasm; do
                    ${pkgs.binaryen}/bin/wasm-opt ${lib.concatStringsSep " " wasmCfg.wasmOptArgs} -o "$f.opt" "$f"
                    mv "$f.opt" "$f"
                  done
                ''
              );

          mkVariantPackage =
            name: binCfg: variantName: variantCfg:
            {
              pkgs,
              craneLib,
              defaultMeta,
              ...
            }:
            let
              # `portable` only matters for native builds.
              effectiveTarget =
                if variantCfg.target != null then
                  variantCfg.target
                else if variantCfg.portable && pkgs.stdenv.hostPlatform.isLinux then
                  "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-unknown-linux-musl"
                else
                  null;

              basePkgs =
                if variantCfg.target != null && config.crossSystems ? ${variantCfg.target} then
                  mkCrossPkgsFor variantCfg.target
                else if variantCfg.portable && pkgs.stdenv.hostPlatform.isLinux then
                  # Static musl build for the host arch: not a fixed triple
                  # in `crossSystems` since it depends on the current arch.
                  #
                  # TODO: Cross compiling a static aarch64 setup in future maybe.
                  import config.inputs.nixpkgs {
                    inherit system;
                    crossSystem.config = effectiveTarget;
                  }
                else if variantCfg.portable && pkgs.stdenv.hostPlatform.isDarwin then
                  # Self-cross to force nixpkgs into system-library-only
                  # linking mode for macos cli type binaries.
                  import config.inputs.nixpkgs {
                    inherit system;
                    crossSystem = pkgs.stdenv.hostPlatform;
                  }
                else
                  pkgs;

              pkgsFor = variantCfg.pkgs {
                inherit lib system;
                target = effectiveTarget;
                pkgs = basePkgs;
              };

              craneLibFor = mkCraneLibFor effectiveTarget pkgsFor;

              injected = {
                inherit lib system;
                target = effectiveTarget;
                pkgs = pkgsFor;
                craneLib = craneLibFor;
              };

              resolvedNativeBuildInputs =
                binCfg.nativeBuildInputs injected ++ variantCfg.nativeBuildInputs injected;
              resolvedBuildInputs = binCfg.buildInputs injected ++ variantCfg.buildInputs injected;

              resolvedInjected = injected // {
                nativeBuildInputs = resolvedNativeBuildInputs;
                buildInputs = resolvedBuildInputs;
              };

              resolvedEnv =
                lib.optionalAttrs (variantCfg.portable && pkgs.stdenv.hostPlatform.isLinux) {
                  CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static -C link-arg=-static";
                }
                // (binCfg.env resolvedInjected)
                // (variantCfg.env resolvedInjected)
                // lib.optionalAttrs (variantCfg.cargoProfile != null) { CARGO_PROFILE = variantCfg.cargoProfile; }
                // lib.optionalAttrs (variantCfg.rustflags != null) { RUSTFLAGS = variantCfg.rustflags; };

              resolvedExtraCraneArgs =
                (binCfg.extraCraneArgs resolvedInjected) // (variantCfg.extraCraneArgs resolvedInjected);

              profileDir =
                if variantCfg.cargoProfile == "dev" then
                  "debug"
                else if variantCfg.cargoProfile == null then
                  "release"
                else
                  variantCfg.cargoProfile;

              baseCommonArgs = {
                src = mkCrateSrc pkgs craneLib name binCfg;
                pname = name;
                strictDeps = true;
                cargoExtraArgs = lib.concatStringsSep " " (
                  lib.filter (s: s != "") [
                    binCfg.cargoExtraArgs
                    variantCfg.extraCargoExtraArgs
                  ]
                );
                nativeBuildInputs = resolvedNativeBuildInputs;
                buildInputs = resolvedBuildInputs;
                env = resolvedEnv;
              }
              // lib.optionalAttrs (effectiveTarget != null || variantCfg.portable) {
                # Cross compiled wasm, static, or portableish stuff can't really
                # check unit tests so don't even try.
                doCheck = false;
              }
              // lib.optionalAttrs (effectiveTarget != null) {
                CARGO_BUILD_TARGET = effectiveTarget;
              };

              overrideCraneArgsFn =
                if variantCfg.overrideCraneArgs != null then
                  variantCfg.overrideCraneArgs
                else
                  binCfg.overrideCraneArgs;
              postProcessFn =
                if variantCfg.postProcess != null then variantCfg.postProcess else binCfg.postProcess;

              commonArgs =
                (overrideCraneArgsFn (injected // { commonArgs = baseCommonArgs; })) // resolvedExtraCraneArgs;

              cargoArtifacts = craneLibFor.buildDepsOnly (commonArgs // { src = depsSrc; });

              # The final build derivation args. Used mostly for wasm builds.
              finalArgs =
                commonArgs
                // lib.optionalAttrs variantCfg.wasm.enable {
                  doInstallCargoArtifacts = false;
                  installPhaseCommand = ''
                    runHook preInstall
                    mkdir -p $out
                    cp -r target/${effectiveTarget}/${profileDir} $out/
                    runHook postInstall
                  '';
                };

              built = craneLibFor.buildPackage (
                finalArgs
                // {
                  inherit cargoArtifacts;
                  meta =
                    defaultMeta
                    // {
                      platforms = [ pkgsFor.stdenv.hostPlatform.system ];
                    }
                    // variantCfg.meta;
                }
              );

              pname = if variantName == "default" then name else "${name}-${variantName}";

              withWasm =
                if variantCfg.wasm.enable then
                  mkWasmOutput {
                    inherit pkgs lib pname;
                    wasmCfg = variantCfg.wasm;
                    wasmPackage = built;
                    wasmFile = "${profileDir}/${name}.wasm";
                  }
                else
                  built;
            in
            postProcessFn (injected // { package = withWasm; });

          binaryOutputs = lib.concatMapAttrs (
            name: binCfg:
            lib.concatMapAttrs (
              variantName: variantCfg:
              lib.optionalAttrs (variantCfg.systems == null || lib.elem system variantCfg.systems) {
                ${if variantName == "default" then name else "${name}-${variantName}"} =
                  mkVariantPackage name binCfg variantName
                    variantCfg;
              }
            ) binCfg.variants
          ) config.binaries;
        in
        {
          # cargo deny with -g support for dep graphviz support, have to look
          # into if I need this any longer.
          cargo-deny-0_19 =
            {
              pkgs,
              lib,
              defaultMeta,
              ...
            }:
            pkgs.rustPlatform.buildRustPackage rec {
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

              # Tests require network access so ignore em.
              doCheck = false;

              meta = defaultMeta // {
                description = "Cargo plugin to help you manage large dependency graphs";
                mainProgram = "cargo-deny";
              };
            };

          # Hacky way to abuse cargo-deny's graph output to generate graphviz
          # dot files and render them to pngs for any duplicate/banned
          # dependencies. Pair with `apps.dotdeps` via nix run .#dotdeps to
          # open the resulting dir containing the pngs, if any were generated that is.
          dotdeps =
            {
              pkgs,
              craneLib,
              ...
            }:
            craneLib.mkCargoDerivation {
              src = toSource {
                root = src;
                inherit (config) fileset;
              };
              pname = "dotdeps";

              nativeBuildInputs = [
                pkgs.graphviz
                pkgs.cargo-audit
                (config.cargoDenyPackage { inherit pkgs lib; })
              ];

              # crane requires cargoArtifacts but like cargoDeny set this to null.
              cargoArtifacts = null;
              doInstallCargoArtifacts = false;

              buildPhaseCargoCommand = ''
                mkdir -p "$out"
                cargo --offline deny check bans licenses sources
                cargo audit -n -d ${config.inputs.advisory-db}
                cargo --offline deny check -g "$out" bans
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
                # gets pulled in cause then you need openssl.
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
        }
        // binaryOutputs;

      # Note for now this is a batteries included setup. That means profiling
      # targets work with all that bs too for whatever its needed for. I end up
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

      # TODO: Pull this out of the flakelight module.
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

      # Here to enable `nix run .#update` to bump flake inputs for the module.
      #
      # TODO: I should enable this to work with cargo upgrade too...
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
      # any were generated, otherwise says so and no-ops out as a non failure.
      #
      # TODO: Should maybe make the default if not in a gui setup to just dump dir?
      apps.dotdeps =
        {
          pkgs,
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
                dir="${pkgs.dotdeps}/graph_output"
                if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
                  printf "no duplicate cargo deps found in %s, nothing to do.\n" "$dir" >&2
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
