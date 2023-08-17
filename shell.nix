with import <nixpkgs> {};
stdenv.mkDerivation {
  name="dan-wireguard-env";
  buildInputs = [
    pkgs.gnumake
    pkgs.iproute2
    pkgs.shellcheck
    pkgs.wireguard-tools
    pkgs.qrencode
  ];
  shellHook = ''
    echo "Finished setting up dan-wireguard-env!"
    echo "Run 'make setup' to configure the wireguard VPN."
  '';
}
