use aws_lc_rs::digest;

fn main() {
    let tag = common::tag();
    let hash = digest::digest(&digest::SHA256, tag.as_bytes());
    let hex = hash.as_ref().iter().map(|b| format!("{b:02x}")).collect::<String>();

    println!("dep: {tag} sha256={hex}");
}
