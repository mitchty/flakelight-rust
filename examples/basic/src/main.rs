fn main() {
    println!("{}", greeting());
}

fn greeting() -> &'static str {
    "hi"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greeting_is_hi() {
        assert_eq!(greeting(), "hi");
    }
}
