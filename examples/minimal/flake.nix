# Minimal example showing how to use this flakelight module.
#
# Note for ci reasons and to force downstream users to be explicit about their
# own nix dependencies, there is no flake.lock file provided for the example
# itself.
#
# You'll be updating the url anyway...
{
  # I named it the same cause I'm a hack but just to be explicit this isn't
  # accelbreads flakelight-rust.
  description = "mitchty/flakelight-rust minimal example";
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

        # Be sure the "portable/static" binary is tested earlier.
        binaries.minimal = {
          variants = {
            default = { };
            portable = {
              portable = true;
            };
          };
        };
      }
    );
}
