{ lib
, stdenvNoCC
, makeWrapper
, bash
, coreutils
, findutils
, gnugrep
, gawk
, git
, util-linux
, nix
}:

stdenvNoCC.mkDerivation {
  pname = "bowenos-tools";
  version = "0.1.0";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib" "$out/libexec/bowenos"
    cp -r bin/. "$out/bin/"
    cp -r lib/. "$out/lib/"
    cp -r libexec/bowenos/. "$out/libexec/bowenos/"

    patchShebangs "$out/bin" "$out/lib" "$out/libexec"

    wrapProgram "$out/bin/bowenos" \
      --set BOWENOS_LIBEXEC_DIR "$out/libexec/bowenos" \
      --prefix PATH : ${lib.makeBinPath [
        bash
        coreutils
        findutils
        gnugrep
        gawk
        git
        util-linux
        nix
      ]}

    runHook postInstall
  '';

  meta = {
    description = "BowenOS tooling CLI for setup, partition, install, and update";
    platforms = lib.platforms.linux;
    mainProgram = "bowenos";
    license = lib.licenses.mit;
  };
}
