# Library-only example showing how to use this flakelight module for a libary
# only crate
#
# Note for ci reasons and to force downstream users to be explicit about their
# own nix dependencies, there is no flake.lock file provided for the example
# itself.
#
# You'll be updating the url anyway...
{
  description = "mitchty/flakelight-rust lib-only example";
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

        # No `binaries.*` entries here on purpose this is meant to demo a
        # library only crate.
      }
    );
}
