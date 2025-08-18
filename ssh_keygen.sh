#!/bin/bash

mkdir -p ~/.ssh

touch ~/.ssh/config
chmod 600 ~/.ssh/config

touch ~/.ssh/authorized_keys
chmod 644 ~/.ssh/authorized_keys

if [[ -f ~/.ssh/id_rsa ]]
then
    echo "~/.ssh/id_rsa already exists"
else
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -b 4096 -C `hostname` -N ""
fi

if [[ -f ~/.ssh/github_id_rsa ]]
then
    echo "~/.ssh/github_id_rsa already exists"
else
    ssh-keygen -f ~/.ssh/github_id_rsa -t rsa -b 4096 -C "github-`hostname`" -N ""
fi

if [[ -f ~/.ssh/gitlab_id_rsa ]]
then
    echo "~/.ssh/gitlab_id_rsa already exists"
else
    ssh-keygen -f ~/.ssh/gitlab_id_rsa -t rsa -b 4096 -C "gitlab-`hostname`" -N ""
fi

if [[ -f ~/.ssh/work_id_rsa ]]
then
    echo "~/.ssh/work_id_rsa already exists"
else
    ssh-keygen -f ~/.ssh/work_id_rsa -t rsa -b 4096 -C "work-`hostname`" -N ""
fi

