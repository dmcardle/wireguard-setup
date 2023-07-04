with import <nixpkgs> {};
stdenv.mkDerivation {
  name="dan-wireguard-env";
  buildInputs = [
    pkgs.gnumake
    pkgs.iproute2
    pkgs.wireguard-tools
  ];
  shellHook = ''
    echo "Now we're ready to rumble! Just run 'make setup'."
  '';
}
