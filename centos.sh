#!/bin/bash
if [ -f ~/centos_updates ]; then
    echo "Updates via rsync already running."
    exit 0
fi

SRC_DIR=rsync://openstack-ci-jenkins@mirrors.msk.mirantis.net/mirrors/centos
DST_DIR=/media/mirrors/mirrors/centos

if [ -d "$DST_DIR" ] ; then
    touch ~/centos_updates
    #rsync -avqSHP --delete --exclude "local*" mirror.yandex.ru::centos/*GPG* $DST_DIR
    #rsync -avqSHP --delete --exclude "local*" --exclude "isos" mirror.nsc.liu.se::centos-store/6.4 $DST_DIR
    #rsync -avqSHP --delete --exclude "local*" --exclude "isos" mirror.yandex.ru::centos/6.5 $DST_DIR
    rsync -avqSHP --delete --exclude "local*" --exclude "isos" $SRC_DIR $DST_DIR
    /bin/rm -f ~/centos_updates
else
    echo "Target directory not present."
fi
