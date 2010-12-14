#!/bin/sh
#################################################################################
# see README for usage
#################################################################################

# parse command line options
while getopts "s:d:r:c:" opt
do
	case "$opt" in
		s) source_zImage=`readlink -f "$OPTARG"`;;
		d) dest_zImage=`readlink -f "$OPTARG"`;;
		r) new_initramfs=`readlink -f "$OPTARG"`;;
		c) compression="$OPTARG";;
	esac
done


i_am=`readlink -f $0`
cur_space=`dirname $i_am`
determiner=0
Image_here="./out/Image"

cd $cur_space
# load functions
. ./lib.sh

if ! [ -f config/compiler.sh ]; then
	echo "COMPILER=/opt/toolchains/arm-2009q3/bin/arm-none-linux-gnueabi" > config/compiler.sh
fi

# load any config files
for x in config/*.sh; do
	. "$x"
done

if [ $COMPILER-gcc > /dev/null = 127 ]  ; then
	echo "****** You must let me know where the compiler is! ******"
	exit 1
fi


if [ -d out ] ; then
	rm -r out && mkdir out
else
	mkdir -p out
fi

echo "##### My name is $0 #####"
if [ "$source_zImage" = "" ]; then
	echo "****** You must let me know where the source zImage file is ******"
	exit 1
else
	echo "##### The source kernel is $source_zImage #####"
fi

if [ "$dest_zImage" = "" ]; then
	echo "****** You must choose a destination file for the resulting zImage ******"
	exit 1
else
	echo "##### The destination zImage file is $dest_zImage #####"
fi

if [ "$new_initramfs" = "" ]; then
	echo "****** You must let me know where the initramfs directory is ******"
	exit 1
elif [ -d $new_initramfs ] ; then
	echo "##### The directory of the initramfs has been selected #####"
elif [ -f $new_initramfs ] ; then
	echo "##### The compressed file of the initramfs has been selected #####"
	initramfs_type="file"
fi

if [ "$compression" = "gzip" ]; then
	echo "##### The initramfs is $new_initramfs (will be gzipped) #####"
	cd $new_initramfs
	find . -print0 | cpio -o0 -H newc | gzip -9 -f > $cur_space/out/initramfs_data.cpio.gz
	new_initramfs=out/initramfs_data.cpio.gz
	cd $cur_space
elif [  "$compression" = "lzma" ]; then
	echo "##### The initramfs is $new_initramfs (will be lzma'ed) #####"
	bash resources/Linux/scripts/gen_initramfs_list.sh -o out/initramfs_data.cpio.lzma  -u "squash"  -g "squash" $new_initramfs
	new_initramfs=out/initramfs_data.cpio.lzma
else
	if [ "$initramfs_type" = "file" ] ; then
		echo "##### The initramfs is $new_initramfs (already compressed) #####"
		new_initramfs=$new_initramfs
	else
		echo "****** You must let me know how you want to compress the initramfs's directory ******"
		exit 1
	fi
fi


analyze_initramfs


if [ $count -lt $determiner ]; then
	echo "##### ERROR : Couldn't match start/end of the initramfs ."
	exit 2
fi

# Check the new initramfs's size
ramdsize=`ls -l $new_initramfs | awk '{print $5}'`

echo "##### 02. The size of the new initramfs is = $ramdsize / original = $count"


if [ $ramdsize -gt $count ]; then
	echo "****** Your initramfs needs to be smaller than the present!! ******"
	exit 2
else
	mv $new_initramfs out/initramfs.cpio
fi

# Check the Image's size
filesize=`ls -l $Image_here | awk '{print $5}'`
echo "##### 03. The size of the Image is $filesize"

# Split the Image #1 ->  head.img
echo "##### 04. Making a head.img ( from 0 ~ $start )"
dd if=$Image_here bs=$start count=1 of=out/head.img

# Split the Image #2 ->  tail.img
echo "##### 05. Making a tail.img ( from $end ~ $filesize )"
dd if=$Image_here bs=$end skip=1 of=out/tail.img

# FrankenStein is being made #1
echo "##### 06. Merging head + initramfs"
cat out/head.img out/initramfs.cpio > out/franken.img

echo "##### 07. Checking the size of [head+initramfs]"
franksize=`ls -l out/franken.img | awk '{print $5}'`

# FrankenStein is being made #2
echo "##### 08. Merging [head+initramfs] + padding + tail"
if [ $franksize -lt $end ]; then
	tempnum=$((end - franksize))
	dd if=/dev/zero bs=$tempnum count=1 of=out/padding
	cat out/padding out/tail.img > out/newtail.img
	cat out/franken.img out/newtail.img > out/new_Image
else
	echo "##### ERROR : Your initramfs is still BIGGER than the stock initramfs #####"
	exit 3
fi

#============================================
# rebuild zImage
#============================================
echo "#=========================================="
echo "##### Now we are rebuilding the zImage #####"
echo "#=========================================="

cd resources/Linux
cp ../../out/new_Image arch/arm/boot/Image

#1. Image -> piggy.gz
echo "##### 09. Image ---> piggy.gz"
gzip -f -9 < arch/arm/boot/compressed/../Image > arch/arm/boot/compressed/piggy.gz

#2. piggy.gz -> piggy.o
echo "##### 10. piggy.gz ---> piggy.o"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.piggy.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/piggy.S

if ! test -f arch/arm/boot/compressed/head.o; then
	#3. head.o
	echo "##### 11. Compiling head"
	$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.head.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/head.o arch/arm/boot/compressed/head.S
fi

if ! test -f arch/arm/boot/compressed/misc.o; then
	#4. misc.o
	echo "##### 12. Compiling misc"
	$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.misc.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -Wall -Wundef -Wstrict-prototypes -Wno-trigraphs -fno-strict-aliasing -fno-common -Werror-implicit-function-declaration -Os -marm -fno-omit-frame-pointer -mapcs -mno-sched-prolog -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8 -msoft-float -Uarm -fno-stack-protector -I/modules/include -fno-omit-frame-pointer -fno-optimize-sibling-calls -g -Wdeclaration-after-statement -Wno-pointer-sign -fwrapv -fpic -fno-builtin -Dstatic=  -D"KBUILD_STR(s)=\#s" -D"KBUILD_BASENAME=KBUILD_STR(misc)"  -D"KBUILD_MODNAME=KBUILD_STR(misc)"  -c -o arch/arm/boot/compressed/misc.o arch/arm/boot/compressed/misc.c
fi

#5. head.o + misc.o + piggy.o --> vmlinux
echo "##### 13. head.o + misc.o + piggy.o ---> vmlinux"
$COMPILER-ld -EL    --defsym zreladdr=0x30008000 --defsym params_phys=0x30000100 -p --no-undefined -X toolchain_resources/libgcc.a -T arch/arm/boot/compressed/vmlinux.lds arch/arm/boot/compressed/head.o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/misc.o -o arch/arm/boot/compressed/vmlinux 

#6. vmlinux -> zImage
echo "##### 14. vmlinux ---> zImage"
$COMPILER-objcopy -O binary -R .note -R .note.gnu.build-id -R .comment -S  arch/arm/boot/compressed/vmlinux arch/arm/boot/zImage

# finishing
echo "##### 15. Getting finished!!"
cp -f arch/arm/boot/zImage $dest_zImage
rm -r arch/arm/boot/compressed/piggy.gz arch/arm/boot/compressed/vmlinux arch/arm/boot/compressed/piggy.o arch/arm/boot/Image arch/arm/boot/zImage ../../out


echo "#=========================================="
echo "##### DONE!! #####"
echo "#=========================================="
