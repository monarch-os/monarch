echo "Update exegol history with new items"


echo "DonPAPI collect -u $USER -p $PASSWORD -d $DOMAIN -t ALL --fetch-pvk --dc-ip $DC_IP" >> ~/.exegol/my-resources/setup/zsh/history
echo "DonPAPI gui" >> ~/.exegol/my-resources/setup/zsh/history
echo "tcpdump -i $INTERFACE icmp and src $VICTIM_IP" >> ~/.exegol/my-resources/setup/zsh/history

