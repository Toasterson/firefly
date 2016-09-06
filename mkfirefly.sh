#!/usr/bin/bash

#Firefly(Rekoning) Failsafe, Recovery and installation image for Illumos. 
#build script

################# Variables ##############

#Commands Used
LDD=/usr/bin/ldd
CP=/usr/gnu/bin/cp
GAWK=/usr/gnu/bin/awk
AWK=${GAWK}
FIND=/usr/gnu/bin/find
TOUCH=/usr/bin/touch
SORT=/usr/bin/sort
UNIQ=/usr/bin/uniq
CAT=/usr/bin/cat
FILE=/usr/bin/file
STRINGS=/usr/gnu/bin/strings
MKDIR=/usr/gnu/bin/mkdir
BASENAME=/usr/gnu/bin/basename
DIRNAME=/usr/gnu/bin/dirname
INSTALL=/usr/gnu/bin/install
TAR=/usr/gnu/bin/tar
MKFILE=/usr/sbin/mkfile
CHMOD=/usr/bin/chmod
LOFIADM=/usr/sbin/lofiadm
NEWFS=/usr/sbin/newfs
MOUNT=/usr/sbin/mount
RM=/usr/gnu/bin/rm
UMOUNT=/usr/sbin/umount
DEVFSADM=/usr/sbin/devfsadm
LS=/usr/gnu/bin/ls
DF=/usr/gnu/bin/df

#Temporary build directory
BAROOT=/tmp/firefly.$$/
BFS=/tmp/nb.$$
#Ramdisk Size
MRSIZE=300M
NBPI=16384
BANAME="boot_archive"

#Used By Script Do Not Edit
LOFIDEV=""
LOFINUM=""
IROOT="/"

################ End Variables ###########

################# Functions ##############

plain() {
    local mesg=$1; shift
    printf "    $_color_bold$mesg$_color_none\n" "$@" >&1
}

quiet() {
    (( _optquiet )) || plain "$@"
}

error() {
    local mesg=$1; shift
    printf "$_color_red==> ERROR:$_color_none $_color_bold$mesg$_color_none\n" "$@" >&2
    return 1
}


add_file() {
    # Add a plain file to the boot_archive image. No parsing is performed and only
    # the singular file is added.
    #   $1: path to file
    #   $2: destination on boot_archive (optional, defaults to same as source)
    #   $3: mode

    (( $# )) || return 1

    # determine source and destination
    local src=$1 dest=${2:-$1} mode=

    if [[ ! -f $IROOT$src ]]; then
        error "file not found: \`%s'" "$IROOT$src"
        return 1
    fi

    mode=${3:-$(stat -c %a "$IROOT$src")}
    if [[ -z $mode ]]; then
        error "failed to stat file: \`%s'." "$IROOT$src"
        return 1
    fi

    if [[ -e $BAROOT$dest ]]; then
        quiet "overwriting file: %s" "$BAROOT$dest"
    else
        quiet "adding file: %s" "$IROOT$src"
    fi
    ${INSTALL} -Dm$mode "$IROOT$src" "$BAROOT$dest"
}


add_binary() {
    # Add a binary file to the boot_archive image. library dependencies will
    # be discovered and added.
    #   $1: path to binary
    #   $2: destination on boot_archive (optional, defaults to same as source)

    local -a sodeps
    local line= regex= binary=$1 dest= mode= sodep= resolved=

    

    if [[ ! -f $IROOT$binary ]]; then
        error "file not found: \`%s'" "$IROOT$binary"
        return 1
    fi

    dest=${2:-$binary}
    mode=$(stat -c %a "$IROOT$binary")

    # always add the binary itself
    add_file "$binary" "$dest" "$mode"

    # negate this so that the RETURN trap is not fired on non-binaries
    ! lddout=$(${LDD} "$IROOT$binary" 2>/dev/null | ${GAWK} '{print $3}') && return 0

    # resolve sodeps
    while read sodep; do
        if [[ $sodep == 'not found' ]]; then
            error "binary dependency not found for \`%s'" "$binary"
            continue
        fi
	if [[ -f $IROOT$sodep && ! -e $BAROOT/$sodep ]]; then
    		add_file "$sodep" "$sodep" "$(stat -Lc %a "$sodep")"
	fi
    done <<< "$lddout"

    return 0
}

remove_junk(){
	local junkentry=$BAROOT/$1
	plain "Removing junk %s" $junkentry
	${RM} -rf $junkentry
}

try_enable_color() {
    local colors

    if ! colors=$(tput colors 2>/dev/null); then
        warning "Failed to enable color. Check your TERM environment variable"
        return
    fi

    if (( colors > 0 )) && tput setaf 0 &>/dev/null; then
        _color_none=$(tput sgr0)
        _color_bold=$(tput bold)
        _color_blue=$_color_bold$(tput setaf 4)
        _color_green=$_color_bold$(tput setaf 2)
        _color_red=$_color_bold$(tput setaf 1)
        _color_yellow=$_color_bold$(tput setaf 3)
    fi
}

usage(){
	echo "mkfirefly [-h] [-i IMAGE_ROOT]"
	echo "-i Use IMAGE_ROOT instead of / as basis of the image"
	echo "-h this usage information"
}

############### End Functions ############


while getopts ":i:h" opt; do
  case $opt in
    i)
	echo "Using Image -$OPTARG as base for firefly"
	IROOT=$OPTARG
	;;
    h)
	usage
	exit 0
	;;
    \?)
	echo "Invalid option: -$OPTARG" >&2
	usage
	exit 1
	;;
    :)
	echo "Option -$OPTARG requires an argument." >&2
	usage
	exit 1
	;;
  esac
done

try_enable_color

for file in $(${CAT} ./firefly.contents); do
	if [ -d $IROOT$file ]; then
		quiet "adding directory: %s" "$IROOT$file"
		${TAR} -C $IROOT -cf - $file | ${TAR} -C $BAROOT -xf -
	elif [ -x $IROOT$file ]; then
		# Add Isaexec Binaries
		FILENAME=$(${BASENAME} $IROOT$file)
		if [ -f $IROOT${file%$FILENAME}amd64/$FILENAME  ]; then
			add_binary ${file%$FILENAME}amd64/$FILENAME
		fi
		if [ -f $IROOT${file%$FILENAME}i86/$FILENAME ]; then
			add_binary ${file%$FILENAME}i86/$FILENAME
		fi
		
		# Add Binary
		add_binary $file
	else
		add_file $file
	fi
done

for entry in $(${CAT} ./firefly.junklist); do
	remove_junk $entry
done

#Make Image
${MKDIR} $BFS
${MKFILE} ${MRSIZE} /tmp/${BANAME}
${CHMOD} o-t /tmp/${BANAME}
LOFIDEV=$(${LOFIADM} -a /tmp/${BANAME})
LOFINUM=$(echo ${LOFIDEV}|${AWK} -F/ '{print $NF}')
echo "y"|env NOINUSE_CHECK=1 ${NEWFS} -o space -m 0 -i ${NBPI} /dev/rlofi/${LOFINUM}
${MOUNT} -Fufs -o nologging $LOFIDEV $BFS

#Populate Image
${TAR} -C $BAROOT -cf - . | ${TAR} -C $BFS -xf -
${TOUCH} $BFS/etc/mnttab
${MKDIR} -p $BFS/dev/fd $BFS/devices/pseudo $BFS/opt $BFS/var $BFS/var/run $BFS/mnt $BFS/system $BFS/system/contract $BFS/system/object $BFS/system/boot $BFS/proc
${DEVFSADM} -r ${BFS}
${RM} -f ${BFS}/dev/dsk/* ${BFS}/dev/rdsk/* ${BFS}/dev/usb/h*
${RM} -f ${BFS}/dev/removable-media/dsk/* ${BFS}/dev/removable-media/rdsk/*
${RM} -fr ${BFS}/dev/zcons/*
#SMF Stuff
$IROOT/lib/svc/method/manifest-import -f $BFS/etc/svc/repository.db -d $IROOT/lib/svc/manifest/

#Some Touch cookies
${TOUCH} $BFS/.autoinstall
${TOUCH} $BFS/.textinstall

#Show How much space we are using in image.
echo "Image Space Usage"
${DF} -h $BFS
${DF} -i $BFS



#Finish Image and show size and name to user
${UMOUNT} $BFS
${LOFIADM} -d /dev/lofi/$LOFINUM
${LS} -alh /tmp/${BANAME}

#Some Cleanup
${RM} -rf $BAROOT
${RM} -rf $BFS
