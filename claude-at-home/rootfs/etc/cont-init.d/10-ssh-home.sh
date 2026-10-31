#!/usr/bin/with-contenv bashio
# OpenSSH resolves ~ from /etc/passwd, not from $HOME, so it would look in
# /root/.ssh — which lives in the container's writable layer and is wiped on
# every rebuild. Point it at the persistent volume instead, so the key
# created below keeps working across restarts, rebuilds and updates.
set -e

readonly SSH_DIR=/data/.ssh
readonly KEY="${SSH_DIR}/id_ed25519"

mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
rm -rf /root/.ssh
ln -sfn "${SSH_DIR}" /root/.ssh

# One key per install, created on first boot so it is ready to hand to
# GitHub before Claude ever needs it.
if [ ! -f "${KEY}" ]; then
    ssh-keygen -t ed25519 -C "claude-at-home" -f "${KEY}" -N "" -q
    bashio::log.info "Created a new SSH key for pushing to Git."
fi

# Pre-trust the common Git hosts, so the first push is not blocked by an
# interactive host key prompt. Best effort — no network yet is fine, the
# prompt still works.
if [ ! -s "${SSH_DIR}/known_hosts" ]; then
    ssh-keyscan -T 5 -t rsa,ecdsa,ed25519 \
        github.com gitlab.com bitbucket.org 2>/dev/null \
        | grep -v '^#' > "${SSH_DIR}/known_hosts" || true
    chmod 600 "${SSH_DIR}/known_hosts"
fi

bashio::log.info "SSH public key — add this to GitHub to let Claude push:"
bashio::log.info "$(cat "${KEY}.pub")"
