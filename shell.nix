with import <nixpkgs> {};
stdenv.mkDerivation {
  name="dan-wireguard-env";
  buildInputs = [
    pkgs.gnumake
    pkgs.iproute2
    pkgs.qrencode
    pkgs.shellcheck
    pkgs.wireguard-tools
    pkgs.yq
  ];
  shellHook = ''
    echo "Finished setting up dan-wireguard-env!"
    echo "If you're not sure what to do, check out the README."
  '';
}
