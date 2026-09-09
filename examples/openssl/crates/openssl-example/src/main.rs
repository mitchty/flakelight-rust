use openssl::hash::{hash, MessageDigest};

fn digest_hex(input: &str) -> String {
    let bytes = hash(MessageDigest::sha256(), input.as_bytes()).expect("openssl digest");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn main() {
    println!("{}", digest_hex("flakelight-rust"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn digest_is_stable() {
        assert_eq!(
            digest_hex("flakelight-rust"),
            "595feaa75db9472ca5446b8261d23c3c65a756944ddf4ee0ea61196408c744fd"
        );
    }
}
