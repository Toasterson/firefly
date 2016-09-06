# Firefly (Reckoning) Recovery and Installation image

This scripts create a boot_archive of a running system.

firefly.contents contains all files and directories that will be copied to the archive.
firefly.junklist contains all directories that will be removed from the archive.

Use -i switch to make a boot archive of another Image. e.g another BE or a Zone.
However you milage may vary depending on the Packages installed in the Image.

To make a bootable ISO use the mkfireflyiso.sh script.
$1 must be the path to the uncompressed boot_archive (generated from mkfirefly.sh)
