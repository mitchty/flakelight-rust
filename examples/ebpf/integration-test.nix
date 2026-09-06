# Use the nixos test suite to validate that eBPF can load in an actual linux vm.
# Not perfect but good enough to help validate the examples build correctly.
#
# Uses the static variant which embedded the eBPF object code from kprobe.
{
  pkgs,
  loaderStatic,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "flakelight-rust-example-ebpf";

  globalTimeout = 5 * 60;

  nodes.machine = _: {
    environment.systemPackages = [ loaderStatic ];
  };

  testScript = ''
    import datetime
    import time

    start_all()
    machine.wait_for_unit("multi-user.target")

    machine.succeed("loader --help")

    # vfs_write fires constantly on most systems, even VMs, so should have
    # actual data quickly.
    machine.succeed(
        "RUST_LOG=info loader --symbol vfs_write "
        "> /tmp/loader.log 2>&1 & echo $! > /tmp/loader.pid"
    )

    time.sleep(2)
    print("loader.log:")
    print(machine.succeed("cat /tmp/loader.log"))

    machine.wait_until_succeeds(
        "grep -q 'attached kprobe' /tmp/loader.log",
        timeout=datetime.timedelta(seconds=15),
    )

    pid = machine.succeed("cat /tmp/loader.pid").strip()
    machine.succeed(f"kill -0 {pid}")

    machine.wait_until_succeeds(
        "grep -q 'generic_kprobe: function trampoline loaded' /tmp/loader.log",
        timeout=datetime.timedelta(seconds=15),
    )

    machine.succeed(f"kill -TERM {pid}")
    machine.wait_until_succeeds(
        f"! kill -0 {pid} 2>/dev/null", timeout=datetime.timedelta(seconds=10)
    )

    print("example-ebpf integration test passed the embedded eBPF kprobe loaded, attached, and fired correctly.")
  '';
}
