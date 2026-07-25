pub fn tag() -> &'static str {
    "extra"
}

pub fn describe() -> String {
    format!("{} + {}", common::tag(), tag())
}
