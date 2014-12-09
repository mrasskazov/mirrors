#!/bin/bash -ex

export LANG=C

# Job parameters
export FUEL_MAIN_BRANCH=${FUEL_MAIN_BRANCH:-master}
only_resync=${only_resync:-false}
MIRROR_POSTFIX=${MIRROR_POSTFIX:-''}
extra_commits=${extra_commits:-''}

# define mirror's build parameters
export BUILD_DIR=../tmp/$(basename $(pwd))/build
export LOCAL_MIRROR=../tmp/$(basename $(pwd))/local_mirror

TOP_DIR=$(cd $(dirname "$0") && pwd)
# Using of config and detect default parameters
source ${TOP_DIR}/build_staging_mirror_config.sh
export RSYNC_MIRROR_HOSTS=${RSYNC_MIRROR_HOSTS:-'osci-mirror-srt.srt.mirantis.net'}

# using of libraries
source $TOP_DIR/functions/locking.sh
source $TOP_DIR/functions/remote_rsync_staging.sh

# getting all of $extra_commits
for commit in $extra_commits; do
    git fetch https://review.openstack.org/stackforge/fuel-main $commit && git cherry-pick FETCH_HEAD
done

# detection of $MIRROR_NAME == $PRODUCT_VERSION
export MIRROR_NAME=${MIRROR_NAME:-$(awk -F '[:=?]' '/^PRODUCT_VERSION\>/ {print $NF}' config.mk)}

# detection of $MIRROR_POSTFIX
if [ -n "$MIRROR_POSTFIX" ]; then
    export MIRROR_NAME="${MIRROR_NAME}-${MIRROR_POSTFIX}"
    export MIRROR_FUEL="http://osci-obs.vm.mirantis.net:82/centos-fuel-${MIRROR_NAME}/centos/"
    export MIRROR_FUEL_UBUNTU="http://osci-obs.vm.mirantis.net:82/ubuntu-fuel-${MIRROR_NAME}/reprepro"
fi
#set docker mirror to srt
export MIRROR_DOCKER=${MIRROR_DOCKER:-http://osci-mirror-srt.srt.mirantis.net/fwm/${MIRROR_NAME}/docker}
# dirty hack for first run
wget -qO /dev/null $MIRROR_DOCKER || export MIRROR_DOCKER=http://osci-mirror-srt.srt.mirantis.net/fwm/5.1/docker

# set global lock
job_lock ${MIRROR_NAME}.lock set

# rebuild mirror
if [ "$only_resync" = "false" ]; then
  make deep_clean
  make USE_MIRROR=none mirror
fi

# Set initial value
BUILD_DESC="Updated: ${MIRROR_NAME}-${STAGING_VERSION_STAMP}<br> "

# sync mirror to remote hosts
for HOST in $RSYNC_MIRROR_HOSTS; do
    HOST_SHORT_NAME="$(get_host_short_name $HOST)"
    rsync_staging_transfer $SRCDIR $HOST $MIRROR_NAME \
        || exit_with_error "Error during sync to $HOST"
    [ "$(echo $BUILD_DESC | grep -o $HOST_SHORT_NAME)" ] \
        && BUILD_DESC+="$(rsync_get_html_link ${HOST_SHORT_NAME}) " \
done

export MIRROR_BASE="$(rsync_get_http_url)"
echo "MIRROR = ${MIRROR_NAME}" > ${WORKSPACE:-"."}/mirror_staging.txt
echo "MIRROR_VERSION = ${STAGING_DIR_NAME}" >> ${WORKSPACE:-"."}/mirror_staging.txt
echo "MIRROR_BASE = $MIRROR_BASE" >> ${WORKSPACE:-"."}/mirror_staging.txt
echo "FUEL_MAIN_BRANCH = ${FUEL_MAIN_BRANCH}" >> ${WORKSPACE:-"."}/mirror_staging.txt
echo ${BUILD_DESC}
