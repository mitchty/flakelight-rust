// Deliberately minimal: this crate exists to prove out the nix
// toolchain/flash wiring in ../../flake.nix, not to be real firmware.
// Blinks whatever GPIO your board's onboard LED is on, adjust as needed.
#![no_std]
#![no_main]

use esp_backtrace as _;
use esp_bootloader_esp_idf::esp_app_desc;
use esp_hal::{
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    main,
};
use esp_println::println;

// espflash gets angy without this
esp_app_desc!();

#[main]
fn main() -> ! {
    let peripherals = esp_hal::init(esp_hal::Config::default());
    let mut led = Output::new(peripherals.GPIO8, Level::Low, OutputConfig::default());
    let delay = Delay::new();

    println!("nostdlib checksum: {}", nostdlib::checksum(&[1, 2, 3]));

    // TODO: why is my dam esp32c3 dev board no blinky? Whatever its an example
    // future mitch figure this out other readers I'm a hack. But a hack that
    // has examples that flash to an esp32 board so its... fine? I dunno I got
    // crap to do.
    const BLINK_MS: u32 = 500;

    // Yes I am that petty in examples.
    const MESSAGES: &[&str] = &[
        "Never gonna give you up",
        "Never gonna let you down",
        "Never gonna run around",
        "And desert you",
        "Never gonna make you cry",
        "Never gonna say goodbye",
        "Never gonna tell a lie",
        "And hurt you",
    ];
    let mut msg_idx: usize = 0;

    loop {
        led.toggle();
        delay.delay_millis(BLINK_MS);
        led.toggle();
        delay.delay_millis(BLINK_MS);

        println!("{}", MESSAGES[msg_idx]);
        msg_idx = (msg_idx + 1) % MESSAGES.len();
    }
}
