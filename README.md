# Wireguard setup

This repo automates the setup of my personal Wireguard VPN.
It requires that you're running a Linux kernel with Wireguard support and that you've installed the Nix package manager.

``` sh
# First, customize the config file for your use case.
cp config.example.yaml config.yaml
$EDITOR config.yaml

# Create keypairs as indicated by config.yaml, generate the server's Wireguard
# config, and bring up the virtual interface.
make start-server

# Generate a config and QR code for a client "foo" that is managed by the
# server. Such clients are listed under `server_managed_keypairs` in the config.
make gen/foo.conf

# Check on the server's status, client statistics, etc.
make status
```

To get started, just run `nix-shell` in this directory, then run `make start-server`.
This will perform the following actions:

* Automatically generate keypairs (if they are not present).
* Add and configure a new Wireguard network interface.

Once the service is running, you can view its status with `make status`.

Manual steps:

1. Write your own config.json file. See the description at the top of the Makefile.
1. If necessary, override the default `SERVER_IFACE` for `make`.
1. If necessary, set up dynamic DNS for home network.
1. Set a static IP address on the Wireguard host.
1. Configure the router to forward UDP port 51820 to the host.
