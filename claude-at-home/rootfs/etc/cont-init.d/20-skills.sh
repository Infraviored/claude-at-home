#!/usr/bin/with-contenv bashio
# Expose the bundled Home Assistant agent skills to Claude.
#
# The skills are baked into the image, not copied into /data, and linked in
# on every boot. That way updating the app also updates the skills, while
# anything you put in /data/.claude/skills yourself is left alone.
set -e

readonly SRC=/opt/ha-skills/skills
readonly DEST=/data/.claude/skills

[ -d "${SRC}" ] || exit 0
mkdir -p "${DEST}"

for skill in "${SRC}"/*; do
    [ -d "${skill}" ] || continue
    name="$(basename "${skill}")"
    target="${DEST}/${name}"

    # Never clobber a real directory - that would be a skill the user
    # installed themselves under the same name.
    if [ -e "${target}" ] && [ ! -L "${target}" ]; then
        bashio::log.warning "Skill '${name}' already exists in your own skills - leaving it alone."
        continue
    fi

    ln -sfn "${skill}" "${target}"
done

bashio::log.info "Home Assistant agent skills linked into ${DEST}."
