#!/bin/sh

curl -s http://packages.elasticsearch.org/GPG-KEY-elasticsearch | sudo apt-key add -
sudo aptitude -q update >/dev/null
sudo aptitude -yq install puppet git
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "host github.com\n   stricthostkeychecking no\n" >~/.ssh/config

if [ -d hula ]; then
  ( cd hula; git pull )
else
  git clone git@github.com:elasticsearch/hula.git >/dev/null
fi

( cd hula && sudo rsync -a puppet /etc )

sudo puppet apply /etc/puppet/manifests/site.pp

