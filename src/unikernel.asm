; =============================================================================
; BareMetal Unikernel
; Copyright (C) 2008-2025 Return Infinity -- see LICENSE.TXT
;
; Initialization code to use BareMetal as a Unikernel.
; It loads the first program listed in BMFS and executes it.
; =============================================================================


BITS 64
ORG 0x001E0000
SIZE equ 512			; Pad unikernel init code to this length

%include 'api/libBareMetal.asm'

start:
	; Clear screen
	mov al, 0x01			; Code for Clear Screen
	call output_char

	; Detect file system for BMFS
	mov rax, 0			; First sector
	mov rcx, 1			; One 4K sector
	mov rdx, 0			; Drive 0
	mov rdi, temp_data
	mov rsi, rdi
	call [b_nvs_read]
	mov eax, [rsi+1024]
	cmp eax, 0x53464d42		; "BMFS"
	jne noFS

	; Load the directory of BMFS
	mov rdi, temp_data
	mov rsi, rdi
	mov rax, 1
	mov rcx, 1
	mov rdx, 0
	call [b_nvs_read]		; Load the 4K BMFS file table

	; Gather file details
	mov rax, [rsi+0x20]		; BMFS File Starting Block
	cmp rax, 0
	je noFile
	shl rax, 9			; Shift left by 9 to convert 2M block to 4K sector
	mov rcx, [rsi+0x30]		; BMFS File Size in bytes

	; Load program to memory
	mov rdi, [ProgramLocation]	; Address to load program to
	add rcx, 4095			; Add 1-byte less of a full sector amount
	shr rcx, 12			; Quick divide by 4096
	mov rdx, 0			; Load from NVS storage device 0
	call [b_nvs_read]		; Load program

	call [ProgramLocation]		; Execute program

	; Shut down the VM
	; mov ecx, SHUTDOWN
	; call [b_system]

	jmp $				; Spin forever as program completed


noFS:
	mov rsi, message_noFS
	call output
	jmp $

noFile:
	mov rsi, message_noFile
	call output
	jmp $				; Spin forever as program completed


; Internal functions

; -----------------------------------------------------------------------------
; string_length -- Return length of a string
;  IN:	RSI = string location
; OUT:	RCX = length (not including the NULL terminator)
;	All other registers preserved
string_length:
	push rdi
	push rax

	xor ecx, ecx
	xor eax, eax
	mov rdi, rsi
	not rcx
	repne scasb			; compare byte at RDI to value in AL
	not rcx
	dec rcx

	pop rax
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output -- Displays text
;  IN:	RSI = message location (zero-terminated string)
; OUT:	All registers preserved
output:
	push rcx

	call string_length		; Calculate the length of the provided string
	call [b_output]			; Output the required number of characters

	pop rcx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_char -- Displays a char
;  IN:	AL  = char to display
; OUT:	All registers preserved
output_char:
	push rsi
	push rcx

	mov [tchar], al			; Store the single character
	mov rsi, tchar			; Load RSI with the address
	mov ecx, 1			; Output only one character
	call [b_output]			; Call the kernel

	pop rcx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; Strings

message_noFS:		db 'No filesystem detected! Halting.', 0
message_noFile:		db 'No file detected! Halting.', 0

; Variables
align 16
ProgramLocation:	dq 0xFFFF800000000000
UEFI_Disk_Offset:	dq 32768

; Temporary data
tchar: db 0, 0, 0
align 16
temp_data: db 0

times SIZE-($-$$) db 0x90	; Set the compiled binary to at least this size in bytes
; =============================================================================
; EOF
