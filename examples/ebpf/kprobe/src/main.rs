#![no_std]
#![no_main]

use aya_ebpf::{macros::kprobe, programs::ProbeContext};
use aya_log_ebpf::info;

/// Generic kprobe trampoline wrapper that fires on every call to whatever
/// kernel symbol the userspace loader attached us to at runtime.
///
/// In spite of the crate name, you can't name this kprobe, there already is
/// another symbol with that name so future me don't name things kprobe...
/// again.
#[kprobe]
pub fn generic_kprobe(ctx: ProbeContext) -> u32 {
    match try_generic_kprobe(ctx) {
        Ok(ret) => ret,
        Err(ret) => ret,
    }
}

fn try_generic_kprobe(ctx: ProbeContext) -> Result<u32, u32> {
    info!(&ctx, "generic_kprobe: function trampoline loaded");
    Ok(0)
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
#[link_section = "license"]
pub static LICENSE: [u8; 13] = *b"Dual MIT/GPL\0";
