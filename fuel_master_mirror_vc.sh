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

export FUEL_MAIN_BRANCH=${FUEL_MAIN_BRANCH:-master}

for commit in $extra_commits; do
    git fetch https://review.openstack.org/stackforge/fuel-main $commit && git cherry-pick FETCH_HEAD
done

export mirror=${mirror:-$(awk -F '[:=?]' '/^PRODUCT_VERSION\>/ {print $NF}' config.mk)}
job_lock ${mirror}.lock set

if [ -n "$MIRROR_POSTFIX" ]; then
    export mirror="${mirror}-${MIRROR_POSTFIX}"
    export MIRROR_FUEL="http://osci-obs.vm.mirantis.net:82/centos-fuel-${mirror}/centos/"
    export MIRROR_FUEL_UBUNTU="http://osci-obs.vm.mirantis.net:82/ubuntu-fuel-${mirror}/reprepro"
fi

if [ "$mirror" = "master" ] && [ -z "$MIRROR_POSTFIX" ] ; then
    export MIRROR_FUEL="http://osci-obs.vm.mirantis.net:82/centos-fuel-${mirror}/centos/"
    export MIRROR_FUEL_UBUNTU="http://osci-obs.vm.mirantis.net:82/ubuntu-fuel-${mirror}/reprepro"
    export EXTRA_RPM_REPOS="extra1,http://osci-obs.vm.mirantis.net:82/centos-fuel-6.1-stable/centos/"
    export EXTRA_DEB_REPOS="http://osci-obs.vm.mirantis.net:82/ubuntu-fuel-6.1-stable/reprepro/ precise main"
fi
#set docker mirror to srt
export MIRROR_DOCKER_HOST=${MIRROR_DOCKER_HOST:-"osci-mirror-srt.srt.mirantis.net"}
export MIRROR_DOCKER_PATH=${MIRROR_DOCKER_PATH:-"fwm/${mirror}/docker"}
export MIRROR_DOCKER="http://$MIRROR_DOCKER_HOST/$MIRROR_DOCKER_PATH"
export RSYNCMODULE='mirror-sync'

export DOCKER_IMAGES=${DOCKER_IMAGES:-'centos(centos:centos6) busybox(busybox)'}
export DOCKER_IMAGES_FORCE_RELOAD=${DOCKER_IMAGES_FORCE_RELOAD:-false}
for IMAGE in $DOCKER_IMAGES; do
    IMAGE_FILE=$(echo $IMAGE | awk -F'[( )]' '{print $1}')
    IMAGE_NAME=$(echo $IMAGE | awk -F'[( )]' '{print $2}')
    # check that image files already on server
    wget -qO - ${MIRROR_DOCKER}/ | grep -Eo ">${IMAGE_FILE}.tar.xz<" \
        && [ "$DOCKER_IMAGES_FORCE_RELOAD" != 'true' ] \
        && continue

    DOCKER_IMAGES_TEMP_DIR=${DOCKER_IMAGES_TEMP_DIR:-$(mktemp -d)}
    docker pull ${IMAGE_NAME} \
        && docker save ${IMAGE_NAME} | xz -zc -4 > ${DOCKER_IMAGES_TEMP_DIR}/${IMAGE_FILE}.tar.xz \
        && rsync -avPzt --include="${IMAGE_FILE}.tar.xz" '--exclude=*' ${DOCKER_IMAGES_TEMP_DIR}/ rsync://$MIRROR_DOCKER_HOST/$RSYNCMODULE/$MIRROR_DOCKER_PATH/ \
        || exit_with_error "Can't get docker image ${IMAGE_NAME}"
done

extra="$extra --del"

only_resync=${only_resync:-false}

if [ "$only_resync" = "false" ]; then
  make deep_clean
  make USE_MIRROR=none mirror
fi

ls ${SRCDIR}/centos/os/x86_64/repodata/
ls ${SRCDIR}/centos/os/x86_64/

mirrors_fail=""

RSYNCUSER=mirror-sync
RSYNCROOT=fwm
FILESROOT=fwm/files

rm -f $TOP_DIR/sync-diff-*.log $TOP_DIR/pkgs-sync-diff-*.log

RSYNCHOST_KHA=osci-mirror-kha.kha.mirantis.net
export RSYNC_EXTRA_PARAMS="--log-file=${TOP_DIR}/sync-diff-kha.log"
rsync_transfer $SRCDIR $RSYNCHOST_KHA || mirrors_fail+=" kha"
RSYNCHOST_MSK=osci-mirror-msk.msk.mirantis.net
export RSYNC_EXTRA_PARAMS="--log-file=${TOP_DIR}/sync-diff-msk.log"
rsync_transfer $SRCDIR $RSYNCHOST_MSK || mirrors_fail+=" msk"
RSYNCHOST_SRT=osci-mirror-srt.srt.mirantis.net
export RSYNC_EXTRA_PARAMS="--log-file=${TOP_DIR}/sync-diff-srt.log"
rsync_transfer $SRCDIR $RSYNCHOST_SRT || mirrors_fail+=" srt"
RSYNCHOST_US=seed-us1.fuel-infra.org
export RSYNC_EXTRA_PARAMS="--log-file=${TOP_DIR}/sync-diff-us1.log"
rsync_transfer $SRCDIR $RSYNCHOST_US || mirrors_fail+=" us_seed"
RSYNCHOST_CZ=seed-cz1.fuel-infra.org
export RSYNC_EXTRA_PARAMS="--log-file=${TOP_DIR}/sync-diff-cz1.log"
rsync_transfer $SRCDIR $RSYNCHOST_CZ || mirrors_fail+=" cz_seed"
unset RSYNC_EXTRA_PARAMS

for F in $TOP_DIR/sync-diff-*.log; do
    grep -E ' <f.* (centos/os/x86_64/Packages/|ubuntu/pool/main/)' $F > $TOP_DIR/pkgs-$(basename $F) \
        || echo "${TGTDIR}: No packages changed." > $TOP_DIR/pkgs-$(basename $F)
done

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
  echo "extra_commits = ${extra_commits}" >> ${WORKSPACE:-"."}/mirror_staging.txt
  echo "Updated: ${MIRROR_VERSION}<br> <a href='http://mirror.fuel-infra.org//${FILESROOT}/${TGTDIR}'>ext</a> <a href='http://${RSYNCHOST_MSK}/${FILESROOT}/${TGTDIR}'>msk</a> <a href='http://${RSYNCHOST_SRT}/${FILESROOT}/${TGTDIR}'>srt</a> <a href='http://${RSYNCHOST_KHA}/${FILESROOT}/${TGTDIR}'>kha</a>"
fi
