# Multi-binary example showing how to use the `binaries` option to build several
# binaries sharing a library crate with per-binary
# fileset/target/env/build-input customization.
#
# Note for ci reasons and to force downstream users to be explicit about
# their own nix dependencies, there is no flake.lock file provided for the
# example itself.
{
  description = "mitchty/flakelight-rust multi-binary example";
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

        # Provide a loosey goose deny.toml setup.
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

        # The server binary is built for windows, the cli only for current platform.
        binaries = {
          server = {
            crate = ./crates/server;
            pathDeps = [ ./crates/common ];

            variants = {
              default = { };
              windows = {
                target = "x86_64-pc-windows-gnu";

                # So that we specify this only builds from here. Bit hacky might
                # fix it later.
                systems = [
                  "x86_64-linux"
                  "aarch64-linux"
                ];
              };
            };
          };

          cli = {
            crate = ./crates/cli;
            pathDeps = [ ./crates/common ];
          };
        };
      }
    );
}
