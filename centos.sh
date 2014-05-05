#!/bin/bash
if [ -f ~/centos_updates ]; then
    echo "Updates via rsync already running."
    exit 0
fi
if [ -d /ex/mirrors/centos/ ] ; then
    touch ~/centos_updates
    rsync -avqhSHP --delete --exclude "local*" mirror.yandex.ru::centos/*GPG* /ex/mirrors/centos/
    rsync -avqhSHP --delete --exclude "local*" --exclude "isos" mirror.nsc.liu.se::centos-store/6.4 /ex/mirrors/centos/
    rsync -avqhSHP --delete --exclude "local*" --exclude "isos" mirror.yandex.ru::centos/6.5 /ex/mirrors/centos/
    /bin/rm -f ~/centos_updates
else
    echo "Target directory not present."
fi
