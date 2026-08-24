//! Minimal library-only example crate for flakelight-rust.

/// Adds two numbers together.
///
/// # Examples
///
/// ```
/// assert_eq!(libonly::add(2, 3), 5);
/// ```
pub fn add(a: i64, b: i64) -> i64 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds() {
        assert_eq!(add(2, 3), 5);
    }
}
