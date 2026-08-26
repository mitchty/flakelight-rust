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
  description = "mitchty/flakelight-rust basic example";
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

        # Be sure the "portable/static" binary is tested earlier.
        #
        # Do NOT rename this binary/crate back to "minimal"... again. Future
        # mitch just trust past mitch ONCE. I even commented this fact.
        binaries.basic = {
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
