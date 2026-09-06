{
  description = "mitchty/flakelight-rust ebpf example with two workspace/flakes for ebpf and loader";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    kprobe.url = "path:./kprobe";
    loader.url = "path:./loader";
  };
  outputs =
    {
      nixpkgs,
      kprobe,
      loader,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: {
        kprobe = kprobe.packages.${system}.kprobe-bpfel;
        loader = loader.packages.${system}.loader;
        loader-static = loader.packages.${system}.loader-static;
      });

      apps = forAllSystems (system: {
        # `nix run .#run-loader -- --symbol sys_openat`
        run-loader =
          let
            pkgs = import nixpkgs { inherit system; };
          in
          {
            type = "app";
            program = "${
              pkgs.writeShellApplication {
                name = "run-loader";
                text = ''
                  exec ${loader.packages.${system}.loader}/bin/loader \
                    --bpf-object ${kprobe.packages.${system}.kprobe-bpfel}/bin/kprobe \
                    "$@"
                '';
              }
            }/bin/run-loader";
          };
      });

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          example-ebpf = pkgs.linkFarmFromDrvs "example-ebpf" (
            builtins.attrValues (kprobe.packages.${system} // kprobe.checks.${system})
            ++ builtins.attrValues (loader.packages.${system} // loader.checks.${system})
          );

          # vm level integration test
          example-ebpf-nixos = import ./integration-test.nix {
            inherit pkgs;
            loaderStatic = loader.packages.${system}.loader-static;
          };
        }
      );
    };
}
