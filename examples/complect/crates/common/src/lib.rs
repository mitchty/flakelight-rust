pub fn tag() -> &'static str {
    "common"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tag_is_stable() {
        assert_eq!(tag(), "common");
    }
}
