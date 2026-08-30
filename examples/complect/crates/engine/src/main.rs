fn main() {
    #[cfg(feature = "cuda")]
    println!("engine cuda version: {}", extra::describe());

    #[cfg(not(feature = "cuda"))]
    println!("engine: {}", extra::describe());

    // NB: If my example wasn't a hack you could even use this in #[test] blocks
    // but basically show using a nostd lib in std land for evil. Though to be
    // honest mostly for testing in a non embedded target prior to it running.
    println!("nostdlib checksum: {}", nostdlib::checksum(&[1, 2, 3]));
}
