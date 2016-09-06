FFBA=$1

DESTDIR=/tmp/iso.$$

mkdir $DESTDIR

tar -C / -cf - boot platform | tar -C $DESTDIR -xf -

cat >> ${DESTDIR}/boot/grub/menu.lst << _EOF
title minimal viable illumos
kernel\$ /platform/i86pc/kernel/\$ISADIR/unix
module\$ /platform/i86pc/boot_archive
title minimal viable illumos (ttya)
kernel\$ /platform/i86pc/kernel/\$ISADIR/unix -B console=ttya,input-device=ttya,output-device=ttya
module\$ /platform/i86pc/boot_archive
title Boot from hard disk
rootnoverify (hd0)
chainloader +1
_EOF

rm -rf ${DESTDIR}/platform/i86pc/boot_archive ${DESTDIR}/platform/i86pc/archive_cache ${DESTDIR}/platform/i86pc/amd64/boot_archive ${DESTDIR}/platform/i86pc/amd64/archive_cache

chmod o-t $FFBA

gzip $FFBA

cp ${FFBA}.gz ${DESTDIR}/platform/i86pc/boot_archive

rm ${FFBA}.gz

cd $DESTDIR

/usr/bin/mkisofs -o /tmp/netboot.iso -b boot/grub/stage2_eltorito \
        -c .catalog \
        -no-emul-boot -boot-load-size 4 -boot-info-table -N -l -R -U \
        -allow-multidot -no-iso-translate -cache-inodes -d -D \
        -V "firefly" ${DESTDIR}
sync

rm -rf $DESTDIR
