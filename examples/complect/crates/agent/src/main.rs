#[cfg(feature = "wasm")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn tag() -> String {
    common::tag().to_string()
}

fn main() {
    #[cfg(feature = "wasm")]
    println!("agent wasm: {}", common::tag());

    #[cfg(not(feature = "wasm"))]
    println!("agent: {}", common::tag());
}
