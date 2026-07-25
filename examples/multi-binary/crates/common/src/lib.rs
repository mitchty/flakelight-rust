pub fn greeting() -> &'static str {
    "hello from the shared common crate"
}

// Really only here to shut cargo nextest up.
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greeting_is_stable() {
        assert_eq!(greeting(), "hello from the shared common crate");
    }
}
