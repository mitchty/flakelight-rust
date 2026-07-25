# Minimal example showing how to use this flakelight module
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
  };
  outputs =
    { flakelight, flakelight-rust, ... }:
    flakelight ./. {
      imports = [ flakelight-rust.flakelightModules.default ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
}
