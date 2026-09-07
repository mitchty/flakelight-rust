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
  version = "0.2.122";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-vO4RSxi/sMWxmsEs3GuljdMfIRSu75A+Q+c5wgYToRU=";
  };
  cargoHash = "sha256-Inup6vvJSG5ghNyeDPyZbfZo4d0LsMG2OJfStoaeDBs=";

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
