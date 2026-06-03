fn main() {
    println!("cargo:rerun-if-changed=winmint-gui.rc");
    println!("cargo:rerun-if-changed=../../assets/brand/icons/winmint_simple_squircle_256.ico");

    if cfg!(target_os = "windows") {
        embed_resource::compile("winmint-gui.rc", embed_resource::NONE)
            .manifest_optional()
            .expect("failed to embed WinMint GUI resources");
    }
}
