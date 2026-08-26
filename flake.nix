# flakelight-rust: crane + fenix module for flakelight shenanigans
# SPDX-License-Identifier: BlueOak-1.0.0
#
# I needed to start unifying all my rust nix flake shenanigans somewhere so here it is.
#
# Its not perfect but I'm sick of copy/pasting all the weirdness I do for my
# crane builds and cross compilation.
{
  description = "mitchty flakelight module rust builds via crane + fenix and shenanigans";

  outputs =
    {
      self,
      flakelight,
      crane,
      fenix,
      flakelight-treefmt,
      flakelight-mitchty,
      advisory-db,
      ...
    }:
    let
      treefmtDefaults = {
        imports = [
          flakelight-treefmt.flakelightModules.default
          flakelight-mitchty.flakelightModules.default
        ];
        treefmtConfig.programs.taplo.enable = true;
      };
    in
    flakelight ./. (
      { lib, ... }:
      {
        imports = [
          flakelight.flakelightModules.extendFlakelight
          treefmtDefaults
        ];
        inputs.self = self;
        nixDir = ./.;

        # These are the default systems this works on. Flakes that import
        # flakelight-rust.nix as a module need to set `systems` themselves.
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        gitHooks.hooks = lib.mkAfter {
          check-examples = {
            enable = true;
            name = "check examples";
            entry = "scripts/test-examples.sh";
            pass_filenames = false;
            stages = [ "pre-push" ];
          };
        };

        flakelightModule =
          { lib, ... }:
          {
            imports = [
              ./flakelight-rust.nix
              treefmtDefaults
            ];
            inputs.crane = lib.mkDefault crane;
            inputs.fenix = lib.mkDefault fenix;
            inputs.advisory-db = lib.mkDefault advisory-db;
          };

        devShell.packages = pkgs: [ pkgs.nil ];

        # Needs network so this can't live in `checks` which build sandboxed.
        # nix run .#check-examples
        apps.check-examples =
          { pkgs, ... }:
          {
            type = "app";
            program = "${
              pkgs.writeShellApplication {
                name = "check-examples";
                runtimeInputs = [
                  pkgs.nix
                  pkgs.git
                ];
                text = ''
                  exec ${./scripts/test-examples.sh} "$@"
                '';
              }
            }/bin/check-examples";
          };
      }
    );

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flakelight = {
      url = "github:nix-community/flakelight";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flakelight-treefmt = {
      url = "github:m15a/flakelight-treefmt";
      inputs = {
        flakelight.follows = "flakelight";
        nixpkgs.follows = "nixpkgs";
      };
    };
    flakelight-mitchty = {
      url = "github:mitchty/flakelight-mitchty";
      # url = "git+http://git.home.arpa:3000/mitch/flakelight-mitchty.git";
      inputs = {
        flakelight.follows = "flakelight";
        nixpkgs.follows = "nixpkgs";
      };
    };
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };
}
