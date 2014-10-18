#!/bin/bash -ex

if [ -z "${prj:=$1}" ]; then
    exit 1
fi

. subr

allowed_branches_var="ALLOWED_BRANCHES_${prj//-/_}"
ALLOWED_BRANCHES="${!allowed_branches_var:-"master milestone-proposed stable/* feature/*"}"

init_repo tmp-repo-$prj
add_github_remote
add_mirantis_remote
git fetch --prune mirantis-$prj --no-tags
git fetch --prune github-$prj
to_push=
for branch in $(find "$GIT_DIR/refs/remotes/github-$prj" -type f); do
    local_ref=${branch##$GIT_DIR/}
    branch_name=${local_ref##refs/remotes/github-$prj/}
    good_branch=false
    for allowed_pat in $ALLOWED_BRANCHES; do
        if [ -z "${branch_name##$allowed_pat}" ]; then
            good_branch=true
            break
        fi
    done
    $good_branch || continue
    remote_ref=refs/heads/$branch_name
    to_push="$to_push $local_ref:$remote_ref"
done

if [ -z "$PRETEND" ]; then
    git push --force mirantis-$prj --tags $to_push
else
    echo "I would run: git push --force mirantis-$prj --tags $to_push"
fi
cleanup_all
