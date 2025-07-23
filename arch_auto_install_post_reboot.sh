#!/bin/bash

fortnite=("Aa" "bb")

function_name() {
	arr=("$@")
   	echo "Parameter #1 is $@"
   	for a in "${arr[*]}"; do
		echo "$a"
	done
}

for service in "${services[@]}"; do
	systemctl enable "$service" --root=/mnt
done

function_name "${fortnite[@]}"

exit 0
# Enable the firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw deny 139
sudo ufw deny 161
sudo ufw deny 5353
sudo ufw limit SSH
