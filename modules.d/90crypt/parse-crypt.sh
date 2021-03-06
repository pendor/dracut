#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
if ! getargbool 1 rd.luks -n rd_NO_LUKS; then
    info "rd.luks=0: removing cryptoluks activation"
    rm -f /etc/udev/rules.d/70-luks.rules
else
    {
        echo 'SUBSYSTEM!="block", GOTO="luks_end"'
        echo 'ACTION!="add|change", GOTO="luks_end"'
    } > /etc/udev/rules.d/70-luks.rules.new

    LUKS=$(getargs rd.luks.uuid rd_LUKS_UUID)
    tout=$(getarg rd.luks.key.tout)

    if [ -n "$LUKS" ]; then
        for luksid in $LUKS; do
            luksid=${luksid##luks-}
            {
                printf -- 'ENV{ID_FS_TYPE}=="crypto_LUKS", '
                printf -- 'ENV{ID_FS_UUID}=="*%s*", ' $luksid
                printf -- 'RUN+="%s --unique --onetime ' $(command -v initqueue)
                printf -- '--name cryptroot-ask-%%k %s ' $(command -v cryptroot-ask)
                printf -- '$env{DEVNAME} luks-$env{ID_FS_UUID} %s"\n' $tout
            } >> /etc/udev/rules.d/70-luks.rules.new


            [ -e $hookdir/initqueue/finished/90-crypt.sh ] || \
            {
                printf -- 'UUIDS=:\n'
                printf -- 'for dm in /dev/dm-*; do\n'
                printf -- '[ -e "$dm" ] || exit 1\n'
                printf -- 'dmid=`/sbin/dmsetup info -c -o uuid --noheadings "$dm"`\n'
                printf -- 'uuid=${dmid#CRYPT-LUKS*-}\n'
                printf -- '[ "x$uuid" = "x$dmid" ] && continue\n'
                printf -- 'UUIDS="${UUIDS}${uuid%%%%-*}:"\n'
                printf -- 'done\n'
            } > $hookdir/initqueue/finished/90-crypt.sh
            uuid=$luksid
            while [ "$uuid" != "${uuid#*-}" ]; do uuid=${uuid%%-*}${uuid#*-}; done
            printf -- '[ "x${UUIDS#*:%s*:}" != "x$UUIDS" ] || exit 1\n' $uuid >> $hookdir/initqueue/finished/90-crypt.sh

            {
                printf -- '[ -e /dev/disk/by-uuid/*%s* ] || ' $luksid
                printf -- 'warn "crypto LUKS UUID "%s" not found"\n' $luksid
            } >> $hookdir/emergency/90-crypt.sh
        done
    else
        {
            printf -- 'ENV{ID_FS_TYPE}=="crypto_LUKS", RUN+="%s ' $(command -v initqueue)
            printf -- '--unique --onetime --name cryptroot-ask-%%k '
            printf -- '%s $env{DEVNAME} luks-$env{ID_FS_UUID} %s"\n' $(command -v cryptroot-ask) $tout
        } >> /etc/udev/rules.d/70-luks.rules.new
    fi

    echo 'LABEL="luks_end"' >> /etc/udev/rules.d/70-luks.rules.new
    mv /etc/udev/rules.d/70-luks.rules.new /etc/udev/rules.d/70-luks.rules
fi
