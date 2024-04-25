#!/bin/bash

# Given a fossil repo (not checked out) and a directory, set up or update
# a git repo based in that directory with the contents of the fossil repo

# If given a third argument, arranges to mirror changes to that location
# Currently accepts adding or changing an external destination and mirrors
# to it when a destination is known, e.g. from a previous invocation

# Should be a no-op when run on a fossil repo that hasn't changed since last time,
# i.e. cron friendly. Doesn't update the mirror if nothing changed.

# Note, better if fossil user contact $USER is set to an email git recognises first

set -e
set -x
set -o pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Check arguments, expected fossil repo, git directory [, external mirror]"
    exit 1
fi

FOSSIL=$1
GITCOPY=$2

EXTERNAL=$3

BRANCH=trunk

if [[ -f "$FOSSIL" ]]
then
    echo "$FOSSIL exists and is a file"
else
    echo "$FOSSIL exists and is not a file, abort"
    exit 1
fi

if [[ -e "$GITCOPY" ]]
then
    if [[ -d "$GITCOPY" ]]
    then
        echo "$GITCOPY exists and is a directory"
    else
        echo "$GITCOPY exists and is not a directory, abort"
        exit 1
    fi
else
    echo "$GITCOPY does not exist, creating directory"
    mkdir "$GITCOPY"
    git init "$GITCOPY" --initial-branch "$BRANCH"
    git -C "$GITCOPY" config user.name $USER
    git -C "$GITCOPY" checkout -b "$BRANCH"

    # Fossil works with a local directory to track things
    # However it also clobbers the existing commits, so to have
    # gitignore present, put it in the fossil repo
    # echo ".mirror_state" > "$GITCOPY"/.gitignore
    # git -C "$GITCOPY" add .gitignore

    # Otherwise rev-parse falls over on an empty repo
    git -C "$GITCOPY" commit --allow-empty -n -m "Initial commit"
fi


if [[ -z $EXTERNAL ]]
then
    echo "No external mirror specified, none will be set up this time"
else
    echo "Setting remote external as $EXTERNAL"
    ! git -C "$GITCOPY" remote remove external
    git -C "$GITCOPY" remote add external "$EXTERNAL"
fi

TMPDIR="$(mktemp -d)"
# Cleanup wants to try all the steps even if some don't succeed
trap 'set +e ; git -C "$GITCOPY" remote remove local ; rm -rf -- "$TMPDIR"' EXIT

GITWORKDIR="$TMPDIR/git"

BEFORE=$(git -C "$GITCOPY" rev-parse "$BRANCH")

# Copy mirror into the temporary git repo
git clone "$GITCOPY" "$GITWORKDIR"

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
git -C "$GITCOPY" checkout "$BRANCH"
! git -C "$GITCOPY" remote remove local # in case previous run failed
git -C "$GITCOPY" remote add local "$GITWORKDIR"
git -C "$GITCOPY" fetch local

# This is like cherry-pick, but it doesn't fall over on empty commits or want an editor window
git -C "$GITCOPY" reset --hard local/"$BRANCH"
git -C "$GITCOPY" rebase "$BRANCH"

AFTER=$(git -C "$GITCOPY" rev-parse "$BRANCH")

if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "No change to underlying repo"
else
    if git -C "$GITCOPY" config remote.external.url > /dev/null;
    then
        echo "Repo changed, external remote configured, pushing to it"
        git -C "$GITCOPY" push external --mirror
    else
        echo "Repo changed but no external mirror defined" ;
    fi
fi  

exit 0
