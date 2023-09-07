# Read configuration from config.json. The config file contains things we may
# not want to check into Git.
#
# Example config.json:
#     {
#         "server_interface": "eth0",
#         "server_hostname": "foo.example",
#         "server_port": 51820,
#         "clients": ["foo-phone", "bar-laptop"],
#         "server_managed_keypairs": ["foo-phone"]
#     }
#
# The commands below extract the necessary information from the config. Debug
# this extraction with `make debug-config`.
ifeq ("$(wildcard config.json)","")
$(error You must create config.json before running make)
endif
SERVER_IFACE            := $(shell jq -r '.server_interface' config.json)
SERVER_HOSTNAME         := $(shell jq -r '.server_hostname' config.json)
SERVER_PORT             := $(shell jq -r '.server_port' config.json)
SERVER_MANAGED_KEYPAIRS := $(shell jq -r '.server_managed_keypairs|join(" ")' config.json)
CLIENTS                 := $(shell jq -r '.clients|join(" ")' config.json)

# Create target names for on-client config files. When generated, these files
# will contain private keys.
CLIENT_CONFIGS       := $(patsubst %, gen/%.conf, $(CLIENTS))
# Create target names for on-server config files that describe the clients.
# These files will not contain private keys.
CLIENT_PEER_SECTIONS := $(patsubst %, gen/%.peer.conf, $(CLIENTS))
# Nix carefully constructs the PATH, but sudo will ignore it by default. This
# command prefix preserves the PATH.
SUDO := sudo env PATH=$$PATH LOCALE_ARCHIVE=/usr/lib/locale/locale-archive

# Generate server-managed keypairs if we don't already have them.
.PHONY: maybe-generate-keypairs
maybe-generate-keypairs:
	@for name in $(SERVER_MANAGED_KEYPAIRS); do \
		KEYPAIR_OUT_DIR="keys-$$name" ; \
		if [ -e "$$KEYPAIR_OUT_DIR" ]; then	\
			echo "Warning: Directory already exists: $$KEYPAIR_OUT_DIR" ; \
		else \
			mkdir "$$KEYPAIR_OUT_DIR" ; \
			umask 077 ; \
			wg genkey > "$$KEYPAIR_OUT_DIR/private" ; \
			wg pubkey < "$$KEYPAIR_OUT_DIR/private" > "$$KEYPAIR_OUT_DIR/public" ; \
			echo "Generated a new keypair in $$KEYPAIR_OUT_DIR" ; \
		fi \
	done

# Generate the Wireguard server config. Note that this file incorporates each of
# the client peer configs.
gen/wg-server.conf: gen maybe-generate-keypairs $(CLIENT_PEER_SECTIONS)
	-rm $@
	echo >> $@ [Interface]
	echo >> $@ Address = 10.8.0.1/24
	echo >> $@ PrivateKey = $$(cat keys-server/private)
	echo >> $@ SaveConfig = true
	echo >> $@ ListenPort = $(SERVER_PORT)
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

# This multi-target rule generates each client's config file. This assumes that
# the required private key is present in keys-${CLIENT_NAME}/.
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
	echo >> $@ Endpoint = $(SERVER_HOSTNAME):$(SERVER_PORT)

# It's not ideal to blast QR codes containing private keys to stdout, but it
# sure is convenient.
	qrencode -t ansiutf8 < $@

gen:
	mkdir -p $@

.PHONY: clean
clean:
	-rm -rf gen/

# The following recipes are shortcuts on top of `wg-quick` for managing the
# server and clients.
#
# TODO: Generate systemd units so the service can start automatically.

.PHONY: status
status:
	${SUDO} wg show

.PHONY: start-server
start-server: gen/wg-server.conf
	${SUDO} wg-quick up $<

.PHONY: stop-server
stop-server: gen/wg-server.conf
	${SUDO} wg-quick down $<

.PHONY: start-client
start-client: gen/${WHICH_CLIENT}.conf
ifndef WHICH_CLIENT
	$(error WHICH_CLIENT must be defined. Possible values are: $(CLIENTS))
endif
	${SUDO} wg-quick up gen/${WHICH_CLIENT}.conf

.PHONY: stop-client
stop-client:
ifndef WHICH_CLIENT
	$(error WHICH_CLIENT must be defined. Possible values are: $(CLIENTS))
endif
	${SUDO} wg-quick down gen/${WHICH_CLIENT}.conf

# The following recipes are only useful for debugging.

.PHONY: debug-config
debug-config: config.json
	@echo "SERVER_IFACE: $(SERVER_IFACE)"
	@echo "SERVER_HOSTNAME: $(SERVER_HOSTNAME)"
	@echo "SERVER_PORT: $(SERVER_PORT)"
	@echo "SERVER_MANAGED_KEYPAIRS: $(SERVER_MANAGED_KEYPAIRS)"
	@echo "CLIENTS: $(CLIENTS)"
	@echo
	@echo "The values above should match the contents of $<:"
	@jq . $<
