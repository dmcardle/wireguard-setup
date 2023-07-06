This repo automates the setup of my personal wireguard VPN.
It requires that you're running a Linux kernel with wireguard support and that you've installed the Nix package manager.

To get started, just run `nix-shell` in this directory, then run `make setup`.
This will perform the following actions:

* Automatically generate keypairs (if they are not present).
* Add and configure a new wireguard network interface.

Manual steps:

1. If necessary, set up dynamic DNS for home network.
1. Set a static IP address on the wireguard host.
1. Configure the router to forward ports.
