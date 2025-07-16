#!/usr/bin/env bash

cd src
nasm unikernel.asm -o ../bin/unikernel.bin -l ../bin/unikernel-debug.txt
