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
      git-hooks,
      advisory-db,
      ...
    }:
    flakelight ./. {
      imports = [
        flakelight.flakelightModules.extendFlakelight
        flakelight-treefmt.flakelightModules.default
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

      flakelightModule =
        { lib, ... }:
        {
          imports = [ ./flakelight-rust.nix ];
          inputs.crane = lib.mkDefault crane;
          inputs.fenix = lib.mkDefault fenix;
          inputs.git-hooks = lib.mkDefault git-hooks;
          inputs.advisory-db = lib.mkDefault advisory-db;
        };

      treefmtConfig = {
        programs.nixfmt.enable = true;
        programs.deadnix.enable = true;
        programs.statix.enable = true;
        programs.taplo.enable = true;

        settings.global.excludes = [
          "*/flake.lock"
        ];
      };

      devShell.packages = pkgs: [ pkgs.nil ];
    };

  inputs = {
    flakelight.url = "github:nix-community/flakelight";
    flakelight-treefmt = {
      url = "github:m15a/flakelight-treefmt";
      inputs.flakelight.follows = "flakelight";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };
}
