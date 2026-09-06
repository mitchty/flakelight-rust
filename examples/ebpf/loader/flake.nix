# Userspace eBPF loader binary.
#
# Linux-only: this loads a bpfel-unknown-none object via BPF syscalls, so
# there's no macOS story here regardless of how portable the userspace binary
# may be.
{
  description = "mitchty/flakelight-rust ebpf example: userspace loader";
  inputs = {
    flakelight.url = "github:nix-community/flakelight";
    flakelight-rust.url = "path:../../..";
    kprobe.url = "path:../kprobe";
  };
  outputs =
    {
      self,
      flakelight,
      flakelight-rust,
      kprobe,
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
        ];

        fileset = lib.fileset.unions [
          (lib.fileset.fileFilter (f: f.hasExt "rs" || f.name == "Cargo.toml") ./.)
          (./. + /Cargo.lock)
          ./deny.toml
        ];

        binaries.loader = {
          variants = {
            default = { };

            # To show how you can build a fully static binary with some provided
            # eBPF object code.
            static = {
              portable = true;
              extraCargoExtraArgs = "--features embedded";

              env =
                { system, ... }:
                {
                  KPROBE_EBPF_OBJECT = "${kprobe.packages.${system}.kprobe-bpfel}/bin/kprobe";
                };
            };
          };
        };
      }
    );
}
