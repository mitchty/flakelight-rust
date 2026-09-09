use openssl::hash::{hash, MessageDigest};

fn digest_hex(input: &str) -> String {
    let bytes = hash(MessageDigest::sha256(), input.as_bytes()).expect("openssl digest");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn main() {
    println!("{}", digest_hex("binaries.openssl-binary"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn digest_is_stable() {
        assert_eq!(
            digest_hex("binaries.openssl-binary"),
            "ace1af713a4464e4c4a160b7110548e7b5695d3db8900f1f7f4fe1d414608c7b"
        );
    }
}
