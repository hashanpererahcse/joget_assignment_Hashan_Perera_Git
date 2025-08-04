#!/bin/bash
apt update
apt install -y openjdk-11-jdk wget unzip apache2

cd /opt
wget https://dev.joget.org/community/downloads/joget-dx7-linux-x64.zip
unzip joget-dx7-linux-x64.zip
chmod +x joget-enterprise-linux-x64.sh
./joget-enterprise-linux-x64.sh install

systemctl start apache2
