fn main() {
    #[cfg(feature = "cuda")]
    println!("engine cuda version: {}", extra::describe());

    #[cfg(not(feature = "cuda"))]
    println!("engine: {}", extra::describe());
}
