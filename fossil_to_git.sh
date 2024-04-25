#!/bin/bash

set -e
set -x
set -o pipefail


if [ "$#" -ne 2 ]; then
    echo "Missing argument, expected fossil repo then git directory"
    exit 1
fi

FOSSIL=$1
MIRROR=$2


BRANCH=trunk
echo "Reflect fossil $1 into git $2"

# Note, better if fossil user contact $USER is set to an email git recognises first

if [[ -f "$FOSSIL" ]]
then
    echo "$FOSSIL exists and is a file"
else
    echo "$FOSSIL exists and is not a file, abort"
    exit 1
fi

if [[ -e "$MIRROR" ]]
then
    if [[ -d "$MIRROR" ]]
    then
        echo "$MIRROR exists and is a directory"
    else
        echo "$MIRROR exists and is not a directory, abort"
        exit 1
    fi
else
    echo "$MIRROR does not exist, creating directory"
    mkdir "$MIRROR"
    git init "$MIRROR" --initial-branch "$BRANCH"
    git -C "$MIRROR" config user.name $USER
    git -C "$MIRROR" checkout -b "$BRANCH"

    # Fossil works with a local directory to track things
    # However it also clobbers the existing commits, so to have
    # gitignore present, put it in the fossil repo
    # echo ".mirror_state" > "$MIRROR"/.gitignore
    # git -C "$MIRROR" add .gitignore

    # Otherwise rev-parse falls over on an empty repo
    git -C "$MIRROR" commit --allow-empty -n -m "Initial commit"
fi

TMPDIR="$(mktemp -d)"
# Cleanup wants to try all the steps even if some don't succeed
trap 'set +e ; git -C "$MIRROR" remote remove local ; rm -rf -- "$TMPDIR"' EXIT

echo "Using TMPDIR $TMPDIR"

GITWORKDIR="$TMPDIR/git"

BEFORE=$(git -C "$MIRROR" rev-parse HEAD)

echo "Before = $BEFORE"

# Copy mirror into the temporary git repo
git clone "$MIRROR" "$GITWORKDIR"

# Export fossil on top of said temporary repo
fossil git export "$GITWORKDIR" -R "$FOSSIL" --mainbranch "$BRANCH"

# git's fast-import doesn't change the working directory
git -C "$GITWORKDIR" checkout HEAD -f

# initial plan was use --debug FILE, edit the text, make a repo from that
# but fossil fatal-errors for not creating a marks file
# instead, here's an aggressive and deprecated git command
# would rather rewrite "$BEFORE"..HEAD but fossil then re-injects the noise
git -C "$GITWORKDIR" filter-branch -f --msg-filter 'grep --text -B1 -E -v "FossilOrigin-Name: [[:alnum:]]"' HEAD

# Update mirror using the contents of said temporary repo
! git -C "$MIRROR" remote remove local # in case previous run failed
git -C "$MIRROR" remote add local "$GITWORKDIR"
git -C "$MIRROR" fetch local

# This is like cherry-pick, but it doesn't fall over on empty commits or want an editor window
git -C "$MIRROR" reset --hard local/"$BRANCH"
git -C "$MIRROR" rebase "$BRANCH"

echo "done"
exit 0
