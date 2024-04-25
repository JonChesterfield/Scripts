#!/bin/bash

# Set up a directory as a git repo that reflects changes from one
# git repo to another, e.g. to export a local one to github
# Takes a non-empty list of branches and only copies those ones.

set -e
set -x
set -o pipefail

if [ "$#" -lt 4 ]; then
    echo "Require internal, external, workdir, branches"
    exit 1
fi

INTERNAL=$1
EXTERNAL=$2
WORKDIR=$3
shift 3
BRANCHES="$@"

echo "Git mirror. From $INTERNAL to $EXTERNAL, workdir $WORKDIR, branches {$BRANCHES}"

if [[ -e "$WORKDIR" ]]
then
    echo "$WORKDIR already exists, abort"
    exit 1
fi


echo "$WORKDIR does not exist, creating directory"
mkdir "$WORKDIR"
git -C "$WORKDIR" init --bare
git -C "$WORKDIR" remote add internal "$INTERNAL"
git -C "$WORKDIR" remote add external "$EXTERNAL"

# Change fetch to apply to the local branches
git -C "$WORKDIR" config remote.internal.fetch '+refs/heads/*:refs/heads/*'

git -C "$WORKDIR" fetch --all
for BRANCH in $BRANCHES; do
    git -C "$WORKDIR" branch "$BRANCH" internal/"$BRANCH"
done

# Github has size limitations. These can be worked around by updating the external
# with pieces that are (probably) smaller than 2gb before using push mirror to put
# the state as it should be. Incremental pushes are hoped to not hit this.

for BRANCH in $BRANCHES; do
    
n=$(git -C "$WORKDIR" rev-list $BRANCH --count)
BATCH=500
for i in $(seq $n -$BATCH 1); do
    echo "Pushing pieces of branch $BRANCH"
    # get the hash of the commit to push
    h=$(git -C "$WORKDIR" log $BRANCH --first-parent --reverse --format=format:%H --skip $i -n1)
    if [[ ! -z "$h" ]]
    then
        echo "Pushing $h..."
        git -C "$WORKDIR" push external ${h}:refs/heads/"$BRANCH" -f
    fi    
done

done

# Handle trailing partial batch and set the external state to what we actually want
git -C $WORKDIR push --mirror external

set +x
echo "To update this mirror:"
echo "git -C $WORKDIR fetch --all && git -C $WORKDIR push --mirror external"
