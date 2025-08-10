; =============================================================================
; BareMetal Unikernel - UEFI
; Copyright (C) 2008-2025 Return Infinity -- see LICENSE.TXT
;
; Initialization code to use BareMetal as a Unikernel.
; It loads the first program listed in BMFS and executes it.
; =============================================================================


BITS 64
ORG 0x001E0000
SIZE equ 256			; Pad unikernel init code to this length

%include 'api/libBareMetal.asm'

start:
	; Clear screen
	mov al, 0x01			; Code for Clear Screen
	call output_char

	; Copy application to correct memory address
	mov rsi, 0x410000
	mov rax, [rsi]
	cmp rax, 0
	je noData
	mov rdi, [ProgramLocation]
	mov rcx, 131072
	rep movsq

	call [ProgramLocation]		; Execute program

	jmp $				; Spin forever as program completed

noData:
	mov rsi, message_noData
	call output
	jmp $


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

message_noData:		db 'No data detected! Halting.', 0

; Variables
align 16
ProgramLocation:	dq 0xFFFF800000000000
;UEFI_Disk_Offset:	dq 32768

; Temporary data
tchar: db 0, 0, 0

times SIZE-($-$$) db 0x90	; Set the compiled binary to at least this size in bytes
; =============================================================================
; EOF
