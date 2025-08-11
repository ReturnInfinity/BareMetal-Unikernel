# BareMetal Unikernel

This repository contains the necessary setup, code, and script to use [BareMetal](https://github.com/ReturnInfinity/BareMetal) as a [Unikernel](https://en.wikipedia.org/wiki/Unikernel). The first program listed in BMFS will be loaded and executed.


### Table of Contents

- [Prerequisites](#prerequisites)
- [Components](#components)
- [Initial configuration](#initial-configuration)
- [Installing the app](#installing-the-app)
- [Running the unikernel](#running-the-unikernel)


# Prerequisites

The script in this repo depends on a Debian-based Linux system like [Ubuntu](https://www.ubuntu.com/download/desktop) or [Elementary](https://elementary.io). macOS is also supported to build and test the OS, as well as the Assembly applications, if you are using [Homebrew](https://brew.sh).

- [NASM](https://nasm.us) - Assembly compiler to build the loader and kernel, as well as the apps written in Assembly.
- [QEMU](https://www.qemu.org) - Computer emulator if you plan on running the OS for quick testing.
- [Git](https://git-scm.com) - Version control software for pulling the source code from GitHub.

In Linux this can be completed with the following command:

	sudo apt install nasm qemu-system-x86 git

In macOS via Homebrew this can be completed with the following command:

	brew install nasm qemu git

 
# Components

BareMetal Unikernel consists of several different projects:

- [Pure64](https://github.com/ReturnInfinity/Pure64) - The software loader.
- [BareMetal](https://github.com/ReturnInfinity/BareMetal) - The kernel.
- [BMFS](https://github.com/ReturnInfinity/BMFS) - The BareMetal File System utility.


# Initial configuration
	
	git clone https://github.com/ReturnInfinity/BareMetal-Unikernel.git
	cd BareMetal-Unikernel
	./baremetal.sh setup
	
`./baremetal.sh setup` automatically runs the build and install functions. Once the setup is complete you can execute `./baremetal.sh YOURAPP.app` to load a program to the disk image and `./baremetal.sh run` to run it.


## Installing the app

	./baremetal.sh YOURAPP.app

This command installs your app to the disk image. The app file should be in `sys`.


## Running the unikernel

	./baremetal.sh run

This command starts `QEMU` to emulate a system. It uses the `bmfs.img` disk image in `sys`.


### Virtual systems

The `bmfs.img` disk image in `sys` can be uploaded to your cloud provider of choice. Otherwise you can create different disk images as follows:

`./baremetal.sh vdi` - Generate VDI disk image for VirtualBox

`./baremetal.sh vmdk` - Generate VMDK disk image for VMware

`./baremetal.sh vpc` - Generate VPC disk image for HyperV


### Physical systems


#### BIOS (legacy systems)

`dd` the `bmfs.img` file from `sys` to a drive.


#### UEFI (modern systems)

Copy `BOOTX64.EFI` from `sys` to you boot medium EFI system partition under `/EFI/BOOT/`.


// EOF
