#!/bin/bash -xe

export STAGING_SAVE_LAST_DAYS="61"
export STAGING_POSTFIX="staging"
export STAGING_VERSION_STAMP=$(date "+%Y-%m-%d-%H%M%S")
export STAGING_VERSION_STAMP_REGEXP='[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}'

export RSYNC_STAGING_EXTRA_PARAMS=""

export RSYNC_MIRROR_USER="mirror-sync"
export RSYNC_MIRROR_ROOTDIR="fwm"
