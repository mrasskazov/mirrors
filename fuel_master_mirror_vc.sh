#!/bin/bash -ex

TOP_DIR=$(cd $(dirname "$0") && pwd)

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH

export BUILD_DIR=../tmp/$(basename $(pwd))/build
export LOCAL_MIRROR=../tmp/$(basename $(pwd))/local_mirror
###

export LANG=C

SRCDIR=${SRCDIR:-$LOCAL_MIRROR}
source $TOP_DIR/rsync_functions.sh
source $TOP_DIR/functions/locking.sh
job_lock ${mirror}.lock set

export FUEL_MAIN_BRANCH=${FUEL_MAIN_BRANCH:-master}
export mirror=${mirror:-$(awk -F '[:=?]' '/^PRODUCT_VERSION\>/ {print $NF}' config.mk)}
if [ -n "$MIRROR_POSTFIX" ]; then
    export mirror="${mirror}-${MIRROR_POSTFIX}"
    export MIRROR_FUEL="http://osci-obs.vm.mirantis.net:82/centos-fuel-${mirror}/centos/"
    export MIRROR_FUEL_UBUNTU="http://osci-obs.vm.mirantis.net:82/ubuntu-fuel-${mirror}/reprepro"
fi
#set docker mirror to srt
export MIRROR_DOCKER=${MIRROR_DOCKER:-http://osci-mirror-srt.srt.mirantis.net/fwm/${mirror}/docker}
# dirty hack for first run
wget -qO /dev/null $MIRROR_DOCKER || export MIRROR_DOCKER=http://osci-mirror-srt.srt.mirantis.net/fwm/5.1/docker

extra="$extra --del"

only_resync=${only_resync:-false}

if [ "$only_resync" = "false" ]; then
  make deep_clean

  for commit in $extra_commits; do
    git fetch https://review.openstack.org/stackforge/fuel-main $commit && git cherry-pick FETCH_HEAD
  done

  make USE_MIRROR=none mirror

fi

ls ${SRCDIR}/centos/os/x86_64/repodata/
ls ${SRCDIR}/centos/os/x86_64/

mirrors_fail=""

RSYNCUSER=mirror-sync
RSYNCROOT=fwm
FILESROOT=fwm/files

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
  echo "Updated: ${MIRROR_VERSION}<br> <a href='http://mirror.fuel-infra.org//${FILESROOT}/${TGTDIR}'>ext</a> <a href='http://${RSYNCHOST_MSK}/${FILESROOT}/${TGTDIR}'>msk</a> <a href='http://${RSYNCHOST_SRT}/${FILESROOT}/${TGTDIR}'>srt</a> <a href='http://${RSYNCHOST_KHA}/${FILESROOT}/${TGTDIR}'>kha</a>"
fi
