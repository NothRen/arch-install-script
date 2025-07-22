#!/bin/bash

# Enable the firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw deny 139
sudo ufw deny 161
sudo ufw deny 5353
sudo ufw limit SSH
