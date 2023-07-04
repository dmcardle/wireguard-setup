# Nix carefully constructs the PATH, but sudo will ignore it by default.
SUDO = sudo env PATH=$$PATH

.PHONY: setup
setup: maybe-generate-keypair setup-link status

# Generate a keypair if we don't already have one.
.PHONY: maybe-generate-keypair
maybe-generate-keypair:
	-./generate-keypair.sh keys
	-./generate-keypair.sh keys-client0

# Based on the instructions at <https://www.wireguard.com/quickstart/>.
.PHONY: setup-link
setup-link:
	-${MAKE} teardown-link
	${SUDO} ip link add dev wg0 type wireguard
	${SUDO} ip address add dev wg0 192.168.2.1/24
	${SUDO} wg set wg0 listen-port 51820		\
		private-key keys/private				\
		peer $$(cat keys-client0/public)$		\
		allowed-ips 192.168.88.0/24				\
		endpoint 209.202.254.14:8172
	${SUDO} ip link set up dev wg0

.PHONY: teardown-link
teardown-link:
	${SUDO} ip link delete dev wg0

.PHONY: status
status:
	${SUDO} env PATH=$$PATH wg show
