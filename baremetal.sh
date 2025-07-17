#!/usr/bin/env bash

set +e
export EXEC_DIR="$PWD"
export OUTPUT_DIR="$EXEC_DIR/sys"

cmd=( qemu-system-x86_64
	-machine q35

# CPU (only 1 cpu type should be uncommented)
	-smp sockets=1,cpus=4
	-cpu Westmere
#	-cpu Westmere,x2apic,pdpe1gb
#	-cpu host -enable-kvm

# RAM
	-m 256 # Value is in Megabytes

# Video
	-device VGA,edid=on,xres=1024,yres=768

# Network configuration. Use one controller.
	-netdev socket,id=testnet1,listen=:1234
	-netdev socket,id=testnet2,listen=:1235
# Intel 82540EM
	-device e1000,netdev=testnet1,mac=10:11:12:08:25:40
#	-device e1000,netdev=testnet2,mac=11:12:13:08:25:40
# Intel 82574L
	-device e1000e,netdev=testnet2,mac=10:11:12:08:25:74
# VIRTIO
#	-device virtio-net-pci,netdev=testnet1,mac=10:11:12:13:14:15 #,disable-legacy=on,disable-modern=false

# Disk configuration. Use one controller.
	-drive id=disk0,file="sys/bmfs.img",if=none,format=raw
# NVMe
#	-device nvme,serial=12345678,drive=disk0
# AHCI
	-device ide-hd,drive=disk0
# VIRTIO
#	-device virtio-blk,drive=disk0 #,disable-legacy=on,disable-modern=false
# Floppy
#	-drive format=raw,file="sys/floppy.img",index=0,if=floppy

# USB
#	-device qemu-xhci # Supports MSI-X
#	-device nec-usb-xhci # Supports MSI-X and MSI
#	-device usb-mouse
#	-device usb-kbd

# Serial configuration
# Output serial to file
	-serial file:"sys/serial.log"
# Output serial to console
#	-chardev stdio,id=char0,logfile="sys/serial.log",signal=off
#	-serial chardev:char0

# Debugging
# Enable monitor mode
	-monitor telnet:localhost:8086,server,nowait
# Enable GDB debugging
#	-s
# Wait for GDB before starting execution
#	-S
# Output network traffic to file
#	-object filter-dump,id=testnet,netdev=testnet,file=net.pcap
# Trace options
#	-trace "e1000e_core*"
#	-trace "virt*"
#	-trace "apic*"
#	-trace "msi*"
#	-trace "usb*"
#	-d trace:memory_region_ops_* # Or read/write
#	-d int # Display interrupts
# Prevent QEMU for resetting (triple fault)
#	-no-shutdown -no-reboot
)

# see if BMFS_SIZE was defined for custom disk sizes
if [ "x$BMFS_SIZE" = x ]; then
	BMFS_SIZE=128
fi

function baremetal_clean {
	rm -rf src/Pure64
	rm -rf src/BareMetal
	rm -rf src/BMFS
	rm -rf src/api
	rm -rf sys
}

function baremetal_setup {
	echo -e "BareMetal OS Setup\n==================="
	baremetal_clean

	mkdir src/api
	mkdir sys

	echo -n "Pulling code from GitHub"

	if [ "$1" = "dev" ]; then
		echo -n " (Dev Env)... "
		setup_args=" -q"
	else
		echo -n "... "
		setup_args=" -q --depth 1"
	fi

	cd src
	git clone https://github.com/ReturnInfinity/Pure64.git $setup_args
	git clone https://github.com/ReturnInfinity/BareMetal.git $setup_args
	git clone https://github.com/ReturnInfinity/BMFS.git $setup_args
	cd ..
	echo "OK"

	cp src/BareMetal/api/libBareMetal.asm src/api/

	# Tweak start sector since the unikernel doesn't use a hybrid disk image
	if [[ "$(uname)" == "Darwin" ]]; then
    		sed -i '' 's/%define DAP_STARTSECTOR 262160/%define DAP_STARTSECTOR 16/g' src/Pure64/src/boot/bios.asm
	else
    		sed -i 's/%define DAP_STARTSECTOR 262160/%define DAP_STARTSECTOR 16/g' src/Pure64/src/boot/bios.asm
	fi

	baremetal_build

	rm sys/bios-floppy*
	rm sys/bios-pxe*
	rm sys/pure64-uefi*
	rm sys/uefi*
	rm sys/bmfslite

	echo -n "Copying software to disk image... "
	baremetal_install
	echo "OK"

	echo -e "\nSetup Complete. Add an app to the image with ./baremetal.sh YOURAPP.app' and then './baremetal.sh run' to start the unikernel."
}

# Initialize disk images
function init_imgs { # arg 1 is BMFS size in MiB
	echo -n "Creating disk image files... "
	cd sys
	dd if=/dev/zero of=bmfs.img count=$1 bs=1048576 > /dev/null 2>&1
	echo "OK"

	cd ..
}

function build_dir {
	cd "$1"
	if [ -e "build.sh" ]; then
		./build.sh
	fi
	if [ -e "install.sh" ]; then
		./install.sh
	fi
	if [ -e "Makefile" ]; then
		make --quiet
	fi
	mv bin/* "${OUTPUT_DIR}"
	cd "$EXEC_DIR"
}

# Build the source code and create the software files
function baremetal_build {
	baremetal_src_check
	echo -n "Assembling source code... "
	
	cd src
	nasm unikernel.asm -o ../sys/unikernel.sys -l ../sys/unikernel-debug.txt
	cd ..
	build_dir "src/Pure64"
	build_dir "src/BareMetal"
	build_dir "src/BMFS"
	echo "OK"

	init_imgs $BMFS_SIZE

	cd "$OUTPUT_DIR"

	# Inject a program binary into to the kernel (ORG 0x001E0000)
	cat pure64-bios.sys kernel.sys unikernel.sys > software.sys

	# Copy software to BMFS for BIOS loading
	dd if=software.sys of=bmfs.img bs=4096 seek=2 conv=notrunc > /dev/null 2>&1

	echo -n "Formatting BMFS disk... "
	./bmfs bmfs.img format
	echo "OK"

	cd ..
}

# Install system software (boot sector, Pure64, kernel) to various storage images
function baremetal_install {
	baremetal_sys_check
	cd "$OUTPUT_DIR"

	# Copy first 3 bytes of MBR (jmp and nop)
	dd if=bios.sys of=bmfs.img bs=1 count=3 conv=notrunc > /dev/null 2>&1
	# Copy MBR code starting at offset 90
	dd if=bios.sys of=bmfs.img bs=1 skip=90 seek=90 count=356 conv=notrunc > /dev/null 2>&1
	# Copy Bootable flag (in case of no mtools)
	dd if=bios.sys of=bmfs.img bs=1 skip=510 seek=510 count=2 conv=notrunc > /dev/null 2>&1

	cd ..
}

function baremetal_run {
	baremetal_sys_check
	echo "Starting QEMU..."

	cmd+=( -name "BareMetal OS" )

	"${cmd[@]}" #execute the cmd string
}

function baremetal_vdi {
	baremetal_sys_check
	echo "Creating VDI image..."
	VDI="3C3C3C2051454D5520564D205669727475616C204469736B20496D616765203E3E3E0A00000000000000000000000000000000000000000000000000000000007F10DABE010001008001000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000600000000000000000000000000000002000000000000000000100000000000001000000000000001000004000000AE8AA5DE02E79043BE0B20DA0E2863EC00D36EACC7B88D4AA988CF098BC1C90200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

	qemu-img convert -O vdi "$OUTPUT_DIR/baremetal_os.img" "$OUTPUT_DIR/BareMetal_OS.vdi"

	echo $VDI > "$OUTPUT_DIR/VDI_UUID.hex"
	xxd -r -p "$OUTPUT_DIR/VDI_UUID.hex" "$OUTPUT_DIR/VDI_UUID.bin"

	dd if="$OUTPUT_DIR/VDI_UUID.bin" of="$OUTPUT_DIR/BareMetal_OS.vdi" count=1 bs=512 conv=notrunc > /dev/null 2>&1

	rm "$OUTPUT_DIR/VDI_UUID.hex"
	rm "$OUTPUT_DIR/VDI_UUID.bin"
}

function baremetal_vmdk {
	baremetal_sys_check
	echo "Creating VMDK image..."
	qemu-img convert -O vmdk "$OUTPUT_DIR/baremetal_os.img" "$OUTPUT_DIR/BareMetal_OS.vmdk"
}

function baremetal_vpc {
	baremetal_sys_check
	echo "Creating VPC image..."
	qemu-img convert -O vpc "$OUTPUT_DIR/baremetal_os.img" "$OUTPUT_DIR/BareMetal_OS.vpc"
}

function baremetal_bnr {
	baremetal_build
	baremetal_install
	baremetal_run
}

function baremetal_app {
	baremetal_sys_check
	cd sys
	if [ -f $1 ]; then
		./bmfs bmfs.img format /force
		./bmfs bmfs.img write $1
		cd ..
	else
		echo "$1 does not exist."
		cd ..
	fi
}

function baremetal_help {
	echo "BareMetal-OS Script"
	echo "Available commands:"
	echo "clean    - Clean the src and bin folders"
	echo "setup    - Clean and setup"
	echo "build    - Build source code"
	echo "install  - Install binary to disk image"
	echo "run      - Run the OS via QEMU"
	echo "vdi      - Generate VDI disk image for VirtualBox"
	echo "vmdk     - Generate VMDK disk image for VMware"
	echo "vpc      - Generate VPC disk image for HyperV"
	echo "bnr      - Build 'n Run"
	echo "*.app    - Install and run an app"
}

function baremetal_src_check {
	if [ ! -d src ]; then
		echo "Files are missing. Please run './baremetal.sh setup' first."
		exit 1
	fi
}

function baremetal_sys_check {
	if [ ! -d sys ]; then
		echo "Files are missing. Please run './baremetal.sh setup' first."
		exit 1
	fi
}

if [ $# -eq 0 ]; then
	baremetal_help
elif [ $# -eq 1 ]; then
	if [ "$1" == "setup" ]; then
		baremetal_setup
	elif [ "$1" == "clean" ]; then
		baremetal_clean
	elif [ "$1" == "build" ]; then
		baremetal_build
	elif [ "$1" == "install" ]; then
		baremetal_install
	elif [ "$1" == "help" ]; then
		baremetal_help
	elif [ "$1" == "run" ]; then
		baremetal_run
	elif [ "$1" == "vdi" ]; then
		baremetal_vdi
	elif [ "$1" == "vmdk" ]; then
		baremetal_vmdk
	elif [ "$1" == "vpc" ]; then
		baremetal_vpc
	elif [ "$1" == "bnr" ]; then
		baremetal_bnr
	elif [[ "$*" == *".app"* ]]; then
		baremetal_app $1
	else
		echo "Invalid argument '$1'"
	fi
elif [ $# -eq 2 ]; then
	if [ "$1" == "build" ]; then
		baremetal_build $2
	elif [ "$1" == "install" ]; then
		baremetal_install $2
	elif [ "$1" == "setup" ]; then
		baremetal_setup $2
	fi
fi
