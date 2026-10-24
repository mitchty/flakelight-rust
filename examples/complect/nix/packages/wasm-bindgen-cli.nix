{
  lib,
  stdenv,
  fetchCrate,
  rustPlatform,
  pkg-config,
  openssl,
  apple-sdk,
}:
rustPlatform.buildRustPackage rec {
  pname = "wasm-bindgen-cli";
  version = "0.2.129";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-pcecKQd7E8Opw6bkFoE569epUi7gh5qpQF1e5PJY6V8=";
  };
  cargoHash = "sha256-vmUrWVU7kPJJxO5qIVeAkwQyWDELO1Z4Z5gitz2kco8=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ apple-sdk ];

  checkFlags = [ "--skip=reference::tests::works" ];

  meta = {
    description = "CLI tool for wasm-bindgen";
    mainProgram = "wasm-bindgen";
  };
}
