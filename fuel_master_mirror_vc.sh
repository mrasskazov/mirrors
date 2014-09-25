#!/bin/bash -ex

TOP_DIR=$(cd $(dirname "$0") && pwd)

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH

export BUILD_DIR=../tmp/$(basename $(pwd))/build
export LOCAL_MIRROR=../tmp/$(basename $(pwd))/local_mirror
###

export LANG=C

export FUEL_MAIN_BRANCH=${FUEL_MAIN_BRANCH:-master}
export mirror=${mirror:-$(awk -F '[:=?]' '/^PRODUCT_VERSION\>/ {print $NF}' config.mk)}
#set docker mirror to srt
export MIRROR_DOCKER=http://fuel-mirror.srt.mirantis.net/fwm/${mirror}/docker
# dirty hack for first run
wget -o - $MIRROR_DOCKER || export MIRROR_DOCKER=http://fuel-mirror.srt.mirantis.net/fwm/5.1/docker

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

RSYNCUSER=mirror-sync
RSYNCROOT=fwm
FILESROOT=fwm/files

SRCDIR=/var/www/fwm/$mirror

#change permissions for packages of current user
sudo chown -R $(id -un):$(id -gn) $SRCDIR

RSYNCHOST_KHA=osci-mirror-kha.kha.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST_KHA || mirrors_fail+=" kha"
RSYNCHOST_MSK=osci-mirror-msk.msk.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST_MSK || mirrors_fail+=" msk"
RSYNCHOST_SRT=osci-mirror-srt.srt.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST_SRT || mirrors_fail+=" srt"
RSYNCHOST_US=seed-us1.fuel-infra.org
rsync_transfer $SRCDIR $RSYNCHOST_US || mirrors_fail+=" us_seed"
RSYNCHOST_CZ=seed-cz1.fuel-infra.org
rsync_transfer $SRCDIR $RSYNCHOST_CZ || mirrors_fail+=" cz_seed"
#workaround for old servers
RSYNCUSER=ostf-mirror
RSYNCHOST_USA=fuel-repository.vm.mirantis.net
rsync_transfer $SRCDIR $RSYNCHOST_USA || mirrors_fail+=" usa_ext"


#rsync /var/www/fwm/$mirror/* ss0078.svwh.net:/var/www/fwm/$mirror/ -r -t -v $extra || mirrors_fail+=" us"

#ssh srv08-srt.srt.mirantis.net sudo rsync -vaP /var/www/fwm/$mirror/ rsync://repo.srt.mirantis.net/repo/fuelweb-repo/$mirror/ -c $extra || mirrors_fail+=" ext"

if [[ -n "$mirrors_fail" ]]; then
  echo Some mirrors failed to update: $mirrors_fail
  exit 1
else
  export MIRROR_VERSION="${TGTDIR}"
  export MIRROR_BASE="http://$RSYNCHOST_MSK/fwm/files/${MIRROR_VERSION}"
  echo "MIRROR = ${mirror}" > ${WORKSPACE:-"."}/mirror_staging.txt
  echo "MIRROR_VERSION = ${MIRROR_VERSION}" >> ${WORKSPACE:-"."}/mirror_staging.txt
  echo "MIRROR_BASE = $MIRROR_BASE" >> ${WORKSPACE:-"."}/mirror_staging.txt
  echo "FUEL_MAIN_BRANCH = ${FUEL_MAIN_BRANCH}" >> ${WORKSPACE:-"."}/mirror_staging.txt
  echo 'Updated: '${MIRROR_VERSION}'<br> <a href="mirror.fuel-infra.org//'$FILESROOT'/'$TGTDIR'">'ext'</a> <a href="http://$RSYNCHOST_MSK/'$FILESROOT'/'$TGTDIR'">'msk'</a> <a href="http://$RSYNCHOST_SRT/'$FILESROOT'/'$TGTDIR'">'srt'</a> <a href="http://$RSYNCHOST_KHA/'$FILESROOT'/'$TGTDIR'">'kha'</a>'
fi
