#!/bin/bash

# Arrange to mirror specific branches from an internal git repo to somewhere else
# For example, export release branches to github without also posting various dev branches
# Takes at least four arguments
# Internal git location
# External git location
# What directory to set up as the staging ground
# One or more branches to mirror

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

# Want git fetch --all to update the local branches and not pull additional branches from the remote
# git fetch --all won't change the local branches, and then push --mirror has nothing to do

# This unfortunately means it'll create a local branch for all remote ones, no deal
# git -C "$WORKDIR" config remote.internal.fetch '+refs/heads/*:refs/heads/*'

# Set up fetch -all to retrive exactly the specified branches
git -C "$WORKDIR" config --unset-all remote.internal.fetch
for BRANCH in $BRANCHES; do
  git -C "$WORKDIR" config --add remote.internal.fetch '+refs/heads/'"$BRANCH"':refs/remotes/internal/'"$BRANCH"
done

git -C "$WORKDIR" fetch --all

# Create local branches with the same names. These are the ones that push --mirror will
# instantiate on the destination.
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
