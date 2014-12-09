#!/bin/bash -xe

export RSYNC_MIRROR_HOSTS="osci-mirror-srt.srt.mirantis.net
osci-mirror-msk.msk.mirantis.net
osci-mirror-kha.kha.mirantis.net
seed-us1.fuel-infra.org
seed-cz1.fuel-infra.org"

function get_host_short_name() {
    # Parameters: HOSTNAME
    if [ "$(echo $1 | grep -o '^seed')" = "seed" ]; then
        echo 'ext'
    else
        echo $1 | grep -oE '\W\w{3}\W' | grep -oE '\w*'
    fi
}
