#!/bin/bash

# Need to check we are running as root, if not then print an error and exit

# insure nala is installed
apt install nala -y

# update, upgrade and clean up from our initial install
nala update
nala full-upgrade -y
nala autoremove --purge -y

# make sure drivers are installed
ubuntu-drivers list
ubuntu-drivers install

# setup so we can install/update google chrome
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list'

# remove apparmor
#systemctl stop apparmor
#systemctl disable apparmor
#systemctl mask apparmor
#nala purge -y apparmor
#nala autoremove --purge -y
#rm -rf /etc/apparmor.d/ /var/lib/apparmor /var/cache/apparmor

# disable ufw
#systemctl stop ufw
#systemctl disable ufw

# get ssh running
nala install -y openssh-server
systemctl enable ssh
systemctl start ssh
systemctl status ssh
