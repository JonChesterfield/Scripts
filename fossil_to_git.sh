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
# trap 'rm -rf -- "$TMPDIR"' EXIT

echo "Using TMPDIR $TMPDIR"

GITIMPORT="$TMPDIR/git.txt"

GITWORKDIR="$TMPDIR/git"


echo "Using $GITIMPORT, $GITWORKDIR"

BEFORE=$(git -C "$MIRROR" rev-parse HEAD)

echo "Before = $BEFORE"


git clone "$MIRROR" "$GITWORKDIR"

# initial plan was use --debug FILE, edit the text, make a repo from that
# but fossil fatal-errors for not creating a marks file
fossil git export "$GITWORKDIR" -R "$FOSSIL" --mainbranch "$BRANCH"

# git's fast-import doesn't change the working directory
git -C "$GITWORKDIR" checkout HEAD -f

# instead, here's an aggressive and deprecated git command
# would rather rewrite "$BEFORE"..HEAD but fossil then re-injects the noise
git -C "$GITWORKDIR" filter-branch -f --msg-filter 'grep --text -B1 -E -v "FossilOrigin-Name: [[:alnum:]]"' HEAD

! git -C "$MIRROR" remote remove local
git -C "$MIRROR" remote add local "$GITWORKDIR"
git -C "$MIRROR" fetch local

git -C "$MIRROR" reset --hard local/"$BRANCH"
git -C "$MIRROR" rebase "$BRANCH"

git -C "$MIRROR" remote remove local

echo "done"
exit 0
