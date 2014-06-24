#!/bin/bash -x

export SRC_MIRR=${1:-Unknown}

TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/mirror_functions.sh

case "$SRC_MIRR" in
    "ubuntu")
        export SRC="rsync://mirrors.msk.mirantis.net/mirrors/${SRC_MIRR}/"
        function additional() {
            date -u > $DST_DIR/project/trace/$(hostname -f)
        }
        #export EXCLUDE="--exclude \"Packages*\" --exclude \"Sources*\" --exclude \"Release*\""
        ;;
    "centos")
        export SRC="rsync://mirrors.msk.mirantis.net/mirrors/${SRC_MIRR}/"
        #export EXCLUDE="--exclude \"local*\" --exclude \"isos\""
        ;;
    "docker")
        export SRC="rsync://mirror.yandex.ru/mirrors/${SRC_MIRR}/"
        export EXCLUDE='--exclude .temp --exclude .lastsync --exclude .mirror.yandex.ru'
        ;;
    "jenkins")
        #SYNCTYPE=wget
        #export SRC="http://pkg.jenkins-ci.org/debian-stable/"
        export SRC="rsync://mirror.yandex.ru/mirrors/jenkins/debian-stable"
        #export EXCLUDE=''
        ;;
    *)
        fatal "Wrong source mirror '$SRC_MIRR'"
esac

job_lock set
via_$SYNCTYPE
clear_old_versions
job_lock unset
