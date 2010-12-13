#!/bin/bash
# initramfs extracter

# parse command line options
while getopts "s:d:" opt
do
	case "$opt" in
		s) source_zImage=`readlink -f "$OPTARG"`;;
		d) dest_initramfs_directory=`readlink -f "$OPTARG"`;;
	esac
done

i_am=`readlink -f $0`
cur_space=`dirname $i_am`
Image_here=$cur_space'/out/Image'
original_initramfs_image=$cur_space'/out/original.cpio'

if [ ! -f "$source_zImage" ]; then
	echo "****** You must specify a valid zImage file as input ******"
	exit 1
fi

if [ ! -n "$dest_initramfs_directory" ]; then
	echo "****** You must specify a directory name where to extract the initramfs ******"
	exit 1
fi

cd $cur_space
mkdir -p out
# load functions
. ./lib.sh

analyze_initramfs

echo "##### reading initramfs from the uncompressed Image file #####"
dd if=$Image_here bs=1 skip=$start count=$count > $original_initramfs_image

rm -r $dest_initramfs_directory
mkdir -p $dest_initramfs_directory || exit 1
cd $dest_initramfs_directory
echo "##### extracting the initramfs in $dest_initramfs_directory #####"
cpio -i --no-absolute-filenames < $original_initramfs_image
