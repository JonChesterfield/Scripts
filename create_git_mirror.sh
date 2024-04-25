#!/bin/bash

# Arrange to mirror specific branches from an internal git repo to somewhere else
# For example, export release branches to github without also posting various dev branches
# Does the initial clone by pushing multiple subsets of the repo to try to avoid a github limit

# Takes at least four arguments
# Internal git location
# External git location
# What directory to set up as the staging ground
# Remainder are one or more branches to mirror

# Example copying from a local machine "wx" to github, a repo > 2gb, some branches of.
# ./create_git_mirror.sh wx:llvm-project git@github.com:JonChesterfield/mirror-llvm.git /tmp/llvm_mirror main jc_varargs_pr jc_varargs_libc

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

if [[ -e "$WORKDIR" ]]
then
    echo "Working directory $WORKDIR already exists, abort"
    exit 1
fi

echo "Creating git mirror. From $INTERNAL to $EXTERNAL, workdir $WORKDIR, branches {$BRANCHES}"

mkdir "$WORKDIR"
git -C "$WORKDIR" init --bare
git -C "$WORKDIR" remote add internal "$INTERNAL"
git -C "$WORKDIR" remote add external "$EXTERNAL"

# Set up fetch -all to retrieve exactly the specified branches
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
    echo "Pushing pieces of branch $BRANCH"
    
    n=$(git -C "$WORKDIR" rev-list "$BRANCH" --count)
    # Larger batch is faster but if it goes over 2gb then github errors out
    # TODO: Could catch the error and dynamically adjust the batch size
    BATCH=5000
    for i in $(seq "$n" -$BATCH 1); do
        echo "Piece $i, total $n"
        # get the hash of the commit to push
        h=$(git -C "$WORKDIR" log "$BRANCH" --first-parent --reverse --format=format:%H --skip $i -n1)
        if [[ ! -z "$h" ]]
        then
            echo "Pushing $h..."
            git -C "$WORKDIR" push external "${h}":refs/heads/"$BRANCH" -f
        fi    
    done
done

# Handle trailing partial batch and set the external state to what we actually want
git -C "$WORKDIR" push --mirror external

set +x
echo "To update this mirror:"
echo "git -C $WORKDIR fetch --all && git -C $WORKDIR push --mirror external"
