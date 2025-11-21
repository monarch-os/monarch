echo "Apply new docker configuration"

jq '.["dns"] = ["10.66.0.1"] | .["bip"] = "10.66.0.1/16" | .["default-address-pools"] = [{"base": "10.67.0.0/16", "size":24}]' /etc/docker/daemon.json | sudo tee /etc/docker/daemon.json > /dev/null
sudo sed -i 's/172.17.0.1/10.66.0.1/' /etc/systemd/resolved.conf.d/20-docker-dns.conf


sudo ufw delete allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53
sudo ufw allow in proto udp from 10.66.0.0/12 to 10.66.0.1 port 53 comment 'allow-docker-dns'

sudo systemctl restart docker
sudo systemctl restart systemd-resolved