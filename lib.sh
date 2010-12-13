# repacker functions

analyze_initramfs()
{
	#==============================================================
	# find start of gziped kernel object in the source zImage file:
	#==============================================================

	pos=`grep -P -a -b --only-matching '\x1F\x8B\x08' $source_zImage | cut -f 1 -d : | grep '1' | awk '(NR==1)'`
	echo "##### 01.  Extracting kernel  from $zImage (start = $pos) to $Image_here"
	dd if=$source_zImage bs=1 skip=$pos | gunzip > $Image_here


	#==========================================================================
	# find start and end of the "cpio" initramfs  inside the kernel object:
	# ASCII cpio header starts with '070701'
	# The end of the cpio archive is marked with an empty file named TRAILER!!!
	#==========================================================================
	start=`grep -a -b --only-matching '070701' $Image_here | head -1 | cut -f 1 -d :`
	end=`grep -a -b --only-matching 'TRAILER!!!' $Image_here | head -1 | cut -f 1 -d :`

	end=$((end + 10))
	count=$((end - start))
}
