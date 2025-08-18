#!/bin/bash

mkdir -p ~/.ssh

touch ~/.ssh/authorized_keys
chmod 644 ~/.ssh/authorized_keys

if [[ -f ~/.ssh/config ]]
then
    echo "~/ssh/config already exists"
else
cat << EOF > ~/.ssh/config
Include ~/.ssh/config.local

Compression yes
IdentitiesOnly yes
ForwardAgent no
ServerAliveInterval 60
ServerAliveCountMax 10

Host github.com-JonChesterfield
  HostName github.com
  IdentityFile ~/.ssh/github_id_rsa
  IdentitiesOnly yes

Host gitlab.com
  HostName gitlab.com
  IdentityFile ~/.ssh/gitlab_id_rsa
  IdentitiesOnly yes

EOF
chmod 600 ~/.ssh/config
fi


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

