#!/bin/bash -ex

TOP_DIR=$(cd $(dirname "$0") && pwd)

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH

export BUILD_DIR=../tmp/$(basename $(pwd))/build
export LOCAL_MIRROR=../tmp/$(basename $(pwd))/local_mirror
###

export LANG=C

mirror=${mirror:-5.1}

if [ $purge_packages = true ]; then
  extra="$extra --del"
fi

only_resync=${only_resync:-false}

if [ "$only_resync" = "false" ]; then
  make deep_clean

  for commit in $extra_commits; do
    git fetch https://review.openstack.org/stackforge/fuel-main $commit && git cherry-pick FETCH_HEAD
  done

  make USE_MIRROR=none mirror
  sudo rsync $LOCAL_MIRROR/* /var/www/fwm/$mirror/ -r -t -v $extra
fi

ls /var/www/fwm/$mirror/centos/os/x86_64/repodata/
ls /var/www/fwm/$mirror/centos/os/x86_64/

sudo createrepo -g /var/www/fwm/$mirror/centos/os/x86_64/comps.xml -o /var/www/fwm/$mirror/centos/os/x86_64 /var/www/fwm/$mirror/centos/os/x86_64

mirrors_fail=""
#ssh jenkins@srv08-srt.srt.mirantis.net sudo chown -R jenkins /var/www/fwm/$mirror/ || true
#rsync /var/www/fwm/$mirror/* srv08-srt.srt.mirantis.net:/var/www/fwm/$mirror/ -r -t -v $extra || mirrors_fail+=" srv08"

source $TOP_DIR/rsync_functions.sh

RSYNCUSER=ostf-mirror
RSYNCROOT=fwm
FILESROOT=fwm/files

SRCDIR=/var/www/fwm/$mirror

RSYNCHOST=fuel-mirror.kha.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST || mirrors_fail+=" kha"
RSYNCHOST=fuel-mirror.msk.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST || mirrors_fail+=" msk"
RSYNCHOST=fuel-mirror.srt.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST || mirrors_fail+=" srt"
RSYNCHOST=fuel-repository.vm.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST || mirrors_fail+=" usa_ext"

#rsync /var/www/fwm/$mirror/* ss0078.svwh.net:/var/www/fwm/$mirror/ -r -t -v $extra || mirrors_fail+=" us"

#ssh srv08-srt.srt.mirantis.net sudo rsync -vaP /var/www/fwm/$mirror/ rsync://repo.srt.mirantis.net/repo/fuelweb-repo/$mirror/ -c $extra || mirrors_fail+=" ext"

if [[ -n "$mirrors_fail" ]]; then
  echo Some mirrors failed to update: $mirrors_fail
  exit 1
fi
