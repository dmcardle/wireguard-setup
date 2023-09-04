# The list of known clients.
CLIENTS := dan-laptop dan-phone zoe-phone
CLIENT_CONFIGS := $(patsubst %, gen/%.conf, $(CLIENTS))
CLIENT_CONFIGS_QR := $(patsubst %, gen/%.conf.qr.png, $(CLIENTS))

SERVER_IFACE ?= wlp33s0

# Nix carefully constructs the PATH, but sudo will ignore it by default.
SUDO = sudo env PATH=$$PATH LOCALE_ARCHIVE=/usr/lib/locale/locale-archive

.PHONY: setup
setup: maybe-generate-keypairs status

# Generate server and client keypairs if we don't already have them.
.PHONY: maybe-generate-keypairs
maybe-generate-keypairs:
	-./generate-keypair.sh keys-server
# List every keypair that should be generated on *this* machine. By default, I'd
# like to generate keypairs on-device.
	-./generate-keypair.sh keys-dan-laptop
	-./generate-keypair.sh keys-dan-phone
	-./generate-keypair.sh keys-zoe-phone

CLIENT_PEER_SECTIONS := $(patsubst %, gen/%.peer.conf, $(CLIENTS))

gen/wg-server.conf: gen maybe-generate-keypairs $(CLIENT_PEER_SECTIONS)
	-rm $@
	echo >> $@ [Interface]
	echo >> $@ Address = 10.8.0.1/24
	echo >> $@ PrivateKey = $$(cat keys-server/private)
	echo >> $@ SaveConfig = true
	echo >> $@ ListenPort = 51820
# Configure iptables on the server to masquerade traffic.
# https://wiki.archlinux.org/title/WireGuard#Server_configuration
	echo >> $@ 'PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $(SERVER_IFACE) -j MASQUERADE'
	echo >> $@ 'PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $(SERVER_IFACE) -j MASQUERADE'
	echo >> $@
	cat >> $@ $(CLIENT_PEER_SECTIONS)

$(CLIENT_PEER_SECTIONS):
	echo >> $@ "# ----- $@ -----"
	echo >> $@ [Peer]
	CLIENT_NAME=$$(basename $@ .peer.conf) && \
		echo >> $@ PublicKey = $$(cat keys-$${CLIENT_NAME}/public) && \
		echo >> $@ AllowedIPs = 10.8.0.$$(./unique_octet_for_client.py $${CLIENT_NAME} ${CLIENTS})/32, 10.8.0.0/24
	echo >> $@

.PHONY: client-configs
client-configs: $(CLIENT_CONFIGS)

# Generate a config for each known client. This assumes that the required
# private key is present in keys-${CLIENT_NAME}/.
$(CLIENT_CONFIGS): gen maybe-generate-keypairs
	-rm $@
	echo >> $@ [Interface]
	CLIENT_NAME=$$(basename $@ .conf) && \
		echo >> $@ Address = 10.8.0.$$(./unique_octet_for_client.py $${CLIENT_NAME} ${CLIENTS})/32
# I couldn't get bidirectional connections with Wireguard on iOS until setting
# the MTU to 1420.
	echo >> $@ MTU = 1420
	echo >> $@ DNS = 8.8.8.8
# Strip "gen/" prefix and ".conf" suffix from the target.
	echo >> $@ PrivateKey = $$(cat keys-$$(basename $@ .conf)/private)
	echo >> $@
	echo >> $@ [Peer]
	echo >> $@ PublicKey = $$(cat keys-server/public)
	echo >> $@ AllowedIPs = 0.0.0.0/0
	echo >> $@ Endpoint = dandandan.mooo.com:51820

	qrencode -t ansiutf8 < $@

gen:
	mkdir -p $@

.PHONY: start-server
start-server: gen/wg-server.conf
	${SUDO} wg-quick up $<

.PHONY: stop-server
stop-server: gen/wg-server.conf
	${SUDO} wg-quick down $<

.PHONY: start-client
start-client: gen/${WHICH_CLIENT}.conf
ifndef WHICH_CLIENT
	@echo Error: WHICH_CLIENT is not defined.
	@echo Possible values are: $(CLIENTS)
	exit 1
endif
	${SUDO} wg-quick up gen/${WHICH_CLIENT}.conf

.PHONY: stop-client
stop-client:
ifndef WHICH_CLIENT
	@echo Error: WHICH_CLIENT is not defined.
	@echo Possible values are: $(CLIENTS)
	exit 1
endif
	${SUDO} wg-quick down gen/${WHICH_CLIENT}.conf

.PHONY: status
status:
	${SUDO} wg show

.PHONY: clean
clean:
	-rm -rf gen/
