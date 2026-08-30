#![cfg_attr(not(test), no_std)]

// `no_std` except under `cfg(test)`: needed so this compiles for the
// firmware binary's `riscv32imc-unknown-none-elf` target, but still gets a
// normal std test harness when run natively via `cargo test`/`cargo
// nextest run` - unit-testing directly on the esp32c3 hardware is a pain.

pub fn checksum(bytes: &[u8]) -> u8 {
    bytes.iter().fold(0u8, |acc, &b| acc.wrapping_add(b))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checksum_of_known_bytes() {
        assert_eq!(checksum(&[1, 2, 3]), 6);
    }
}
