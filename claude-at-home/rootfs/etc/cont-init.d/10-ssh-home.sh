#!/usr/bin/with-contenv bashio
# OpenSSH resolves ~ from /etc/passwd, not from $HOME, so it would look in
# /root/.ssh — which lives in the container's writable layer and is wiped on
# every rebuild. Point it at the persistent volume instead, so a key created
# once keeps working across restarts, rebuilds and updates.
set -e

mkdir -p /data/.ssh
chmod 700 /data/.ssh

rm -rf /root/.ssh
ln -sfn /data/.ssh /root/.ssh
