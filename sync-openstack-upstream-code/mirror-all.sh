#!/bin/bash -ex

PS4="+mirror-all> "
. subr

mirror_one="$(dirname $0)/mirror-one.sh"
: ${MIRANTIS_USERNAME:=openstack-ci-mirrorer-jenkins}
: ${GERRIT_HOST:=review.fuel-infra.org}
export MIRANTIS_USERNAME GERRIT_HOST
add_all_projects
for prj in $PROJECTS; do
    case $prj in
        *murano* ) ;;
        * ) continue;;
    esac
    export ALLOWED_BRANCHES_${prj//-/_}="master milestone-proposed stable/* feature/* release-*"
done
failed_prjs=""
succeeded_prjs=""

exec 4> results.xml
echo "<testsuite>" >&4

declare -A child_pid
for prj in $PROJECTS; do
    (setup_prefixes "#${prj}"; "$mirror_one" $prj) &
    child_pid[$prj]=$!
done

for prj in $PROJECTS; do
    if wait ${child_pid[$prj]}; then
        succeeded_prjs="$succeeded_prjs $prj"
        echo "<testcase classname=\"mirror\" name=\"$prj\" />" >&4
    else
        failed_prjs="$failed_prjs $prj"
        echo "<testcase classname=\"mirror\" name=\"$prj\"><failure /></testcase>" >&4
    fi
done

echo "</testsuite>" >&4

if [ "$succeeded_prjs" ]; then
    echo "SUCEEDED: $succeeded_prjs"
fi
if [ "$failed_prjs" ]; then
    echo "FAILED: $failed_prjs"
    exit 1
fi
