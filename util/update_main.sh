#!/bin/bash

REV=$(git rev-parse HEAD) && git reset --hard HEAD~1 && git pull && git cherry-pick $REV
