#!/bin/bash

als="$(cat $HOME/.bashrc | grep sysup)"
nr="$(dpkg -l needrestart | grep 'no description available')"

if [ -z "$als" ]; then
  echo "alias sysup=$PWD/sysup.sh" >> $HOME/.bashrc
fi

if [ -z "$nr" ]; then
  sudo apt-get purge needrestart -y
  echo $nr
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
sudo DEBIAN_FRONTEND=noninteractive apt-get autoclean -y
