fn main() {
    let hex = std::env::var("MULTISIG_PROGRAM_ID_HEX").unwrap_or_default();
    println!("cargo:rustc-env=MULTISIG_PROGRAM_ID_HEX={}", hex);
    println!("cargo:rerun-if-env-changed=MULTISIG_PROGRAM_ID_HEX");
}
