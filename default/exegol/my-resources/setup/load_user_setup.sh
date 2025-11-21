#!/bin/bash
set -e

# This script will be executed on the first startup of each new container with the "my-resources" feature enabled.
# Arbitrary code can be added in this file, in order to customize Exegol (dependency installation, configuration file copy, etc).
# It is strongly advised **not** to overwrite the configuration files provided by exegol (e.g. /root/.zshrc, /opt/.exegol_aliases, ...), official updates will not be applied otherwise.

# Exegol also features a set of supported customization a user can make.
# The /opt/supported_setups.md file lists the supported configurations that can be made easily.

# Install kitty
apt update && apt install -y kitty
ln -s /opt/my-resources/setup/kitty ~/.config/kitty

# Install chaos client
go install -v github.com/projectdiscovery/chaos-client/cmd/chaos@latest

# Install notify
go install -v github.com/projectdiscovery/notify/cmd/notify@latest

# Configure subfinder
mkdir -p /root/.config/subfinder/
cp /opt/my-resources/setup/subfinder/provider-config.yaml /root/.config/subfinder/

# Configure notify
mkdir -p /root/.config/notify/
cp /opt/my-resources/setup/notify/provider-config.yaml /root/.config/notify/

# Configure shodan
mkdir -p  /root/.config/shodan
cp /opt/my-resources/setup/shodan /root/.config/shodan/api_key

# Install leviathan
go install forge.tedomum.net/kludge/leviathan@latest
mkdir -p ~/.config/leviathan/
cp -r /opt/my-resources/setup/leviathan/* /root/.config/leviathan/

# Update Project Discovery tools
nuclei -update && nuclei -ut
httpx -update
subfinder -update

# Refresh asdf
asdf reshim

