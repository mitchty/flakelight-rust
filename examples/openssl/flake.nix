# Example showing how to add a c library dep into this whole rigamarole.
#
# Here as the cargo-workspace-deps setup needs to be able to know about cargo
# deps for things like clippy and doc derivations. Without that it fails to link
# even if the binaries are linked to openssl etc...
{
  description = "mitchty/flakelight-rust openssl example";
  inputs = {
    flakelight.url = "github:nix-community/flakelight";
    flakelight-rust.url = "path:../..";
  };
  outputs =
    {
      self,
      flakelight,
      flakelight-rust,
      ...
    }:
    flakelight ./. (
      { lib, ... }:
      {
        imports = [ flakelight-rust.flakelightModules.default ];
        inputs.self = self;

        # Make `.#default`/`packages.default` build `openssl-binary` instead
        # of the generic whole-workspace package.
        defaultBinary = "openssl-binary";

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        # Provide a loosey goose deny.toml setup.
        fileset = lib.fileset.unions [
          (lib.fileset.fileFilter (f: f.hasExt "rs" || f.name == "Cargo.toml") ./.)
          (./. + /Cargo.lock)
          ./deny.toml
        ];

        # This is for the workspace level derivations to be able to at least
        # link to openssl. NB: pkg-config is here cause openssl uses it, not
        # required otherwise really but that would be another example.
        buildInputs =
          { pkgs, ... }:
          [ pkgs.openssl ];

        nativeBuildInputs =
          { pkgs, ... }:
          [ pkgs.pkg-config ];

        env =
          {
            pkgs,
            lib,
            buildInputs,
            ...
          }:
          {
            OPENSSL_DIR = "${pkgs.openssl.dev}";
            OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
            OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include/";
            # Here for the nextest derivation so it can link/load libssl.so.3 at
            # runtime within the nix sandbox itself. Bit of an edge case.
            LD_LIBRARY_PATH = "$LD_LIBRARY_PATH:${lib.makeLibraryPath buildInputs}";
          };

        # This is basically basic + ^^^^ all that crap its nothing special.
        #
        # The only interesting bits are really in the crate in that we build the
        # portable variant of openssl rust code so we can get truly static final
        # binaries. Macos doesn't need the patchelf shenanigans linux does. And
        # windows is basically treated like musl static builds.
        binaries.openssl-binary = {
          crate = ./crates/openssl-binary;

          variants = {
            default = {
              rustflags = "-D warnings";

              buildInputs =
                { pkgs, ... }:
                [ pkgs.openssl ];

              nativeBuildInputs =
                { pkgs, ... }:
                [ pkgs.pkg-config ];

              env =
                {
                  pkgs,
                  lib,
                  buildInputs,
                  ...
                }:
                {
                  OPENSSL_DIR = "${pkgs.openssl.dev}";
                  OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
                  OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include/";
                  # Here for the nextest derivation so it can link/load libssl.so.3 at
                  # runtime within the nix sandbox itself. Bit of an edge case.
                  LD_LIBRARY_PATH = "$LD_LIBRARY_PATH:${lib.makeLibraryPath buildInputs}";
                };

              # Fixup RPATH so that nix run .#binary works correctly on linux
              # for dynamic binaries.
              #
              # On mach-o binaries cargo sets up the linker to bake the path
              # directly into the binary so basically we get this for free on
              # macos though its not "portable" to non nix systems it at least
              # nix run's.
              #
              # The windows variant behaves the same as a static linux build to
              # avoid dll shenanigans as noted.
              extraCraneArgs =
                {
                  lib,
                  pkgs,
                  buildInputs,
                  ...
                }:
                {
                  postFixup = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                    if [ -d "$out/bin" ]; then
                      for f in "$out"/bin/*; do
                        [ -f "$f" ] || continue
                        patchelf --add-rpath ${lib.makeLibraryPath buildInputs} "$f"
                      done
                    fi
                  '';
                };
            };

            portable = {
              portable = true;
              extraCargoExtraArgs = "--features vendored";

              nativeBuildInputs =
                { pkgs, ... }:
                [ pkgs.perl ];
            };

            windows = {
              target = "x86_64-pc-windows-gnu";
              extraCargoExtraArgs = "--features vendored";

              nativeBuildInputs =
                { pkgs, ... }:
                [ pkgs.perl ];

              systems = [
                "x86_64-linux"
                "aarch64-linux"
              ];
            };
          };
        };
      }
    );
}
