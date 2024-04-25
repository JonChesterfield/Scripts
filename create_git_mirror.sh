#!/bin/bash

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

TMPDIR="$(mktemp -d)"
trap 'rm -rf -- "$TMPDIR"' EXIT


echo "$WORKDIR does not exist, creating directory"
mkdir "$WORKDIR"
git -C "$WORKDIR" init --bare
git -C "$WORKDIR" remote add internal "$INTERNAL"
git -C "$WORKDIR" remote add external "$EXTERNAL"
git -C "$WORKDIR" fetch --all
for BRANCH in $BRANCHES; do
    git -C "$WORKDIR" branch "$BRANCH" internal/"$BRANCH"
done

set +x
echo "To update this mirror:"
echo "git -C $WORKDIR fetch --all && git -C $WORKDIR push --mirror external"
