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
CLIENT_CONFIGS          := $(patsubst %, gen/%.conf, $(CLIENTS))
# Create target names for on-server config files that describe the clients.
# These files will not contain private keys.
CLIENT_PEER_SECTIONS    := $(patsubst %, gen/%.peer.conf, $(CLIENTS))
# Create names for phony targets that bring up/down individual peer interfaces.
ALL_PEERS_START_TARGETS := $(patsubst %, start-%, server $(CLIENTS))
ALL_PEERS_STOP_TARGETS  := $(patsubst %, stop-%, server $(CLIENTS))
# Create target names for private and public keys.
SERVER_MANAGED_PRIVATE_KEYS := $(patsubst %, keys-%/private, $(SERVER_MANAGED_KEYPAIRS))
SERVER_MANAGED_PUBLIC_KEYS  := $(patsubst %, keys-%/public, $(SERVER_MANAGED_KEYPAIRS))
# Nix carefully constructs the PATH, but sudo will ignore it by default. This
# command prefix preserves the PATH.
SUDO := sudo env PATH=$$PATH LOCALE_ARCHIVE=/usr/lib/locale/locale-archive

$(SERVER_MANAGED_PRIVATE_KEYS):
	if [ ! -e $@ ]; then \
		mkdir -p $$(dirname $@) && \
		umask 077 && wg genkey > $@ ; \
	fi

$(SERVER_MANAGED_PUBLIC_KEYS):
	if [ ! -e $@ ]; then \
		$(MAKE) $$(dirname $@)/private && \
		umask 077 && wg pubkey < $$(dirname $@)/private > $@ ; \
	fi

# Generate the Wireguard server config. Note that this file incorporates each of
# the client peer configs.
gen/server.conf: gen keys-server/private $(CLIENT_PEER_SECTIONS)
	-rm -f $@
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

$(CLIENT_PEER_SECTIONS): $(SERVER_MANAGED_PUBLIC_KEYS)
	echo >> $@ "# ----- $@ -----"
	echo >> $@ [Peer]
	CLIENT_NAME=$$(basename $@ .peer.conf) && \
		echo >> $@ PublicKey = $$(cat keys-$${CLIENT_NAME}/public) && \
		echo >> $@ AllowedIPs = 10.8.0.$$(./unique_octet_for_client.py $${CLIENT_NAME} ${CLIENTS})/32, 10.8.0.0/24
	echo >> $@

# This multi-target rule generates each client's config file. This assumes that
# the required private key is present in keys-${CLIENT_NAME}/.
$(CLIENT_CONFIGS): gen keys-server/public $(SERVER_MANAGED_PRIVATE_KEYS)
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

.PHONY: $(ALL_PEERS_START_TARGETS)
$(ALL_PEERS_START_TARGETS):
	peer_config=gen/$$(sed s/start-// <<< $@).conf && \
		${MAKE} $$peer_config && \
		${SUDO} wg-quick up $$peer_config

.PHONY: $(ALL_PEERS_STOP_TARGETS)
$(ALL_PEERS_STOP_TARGETS):
	peer_config=gen/$$(sed s/stop-// <<< $@).conf && \
		${MAKE} $$peer_config && \
		${SUDO} wg-quick down $$peer_config

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
