bits 64
default rel

; System defines

SYS_exit        equ 0x02000000 + 1
SYS_read        equ 0x02000000 + 3
SYS_write       equ 0x02000000 + 4
SYS_ioctl       equ 0x02000000 + 54
SYS_fcntl       equ 0x02000000 + 92
SYS_select      equ 0x02000000 + 93

STDIN_FILENO    equ 0
STDOUT_FILENO   equ 1

TIOCGETP        equ 0x40067408
TIOCSETP        equ 0x80067409

CBREAK          equ 0x00000002  ; half-cooked mode
ECHO            equ 0x00000008  ; echo input

F_SETFL         equ 0x00000004
O_NONBLOCK      equ 0x00000004

struc sgttyb
	.sg_ispeed: resb    1
	.sg_ospeed: resb    1
	.sg_erase:  resb    1
	.sg_kill:   resb    1
	.sg_flags:  resw    1
endstruc

struc timeval
	; resq: reserve quadword (64 bits)
	.tv_sec:    resq    1
	.tv_nsec:   resq    1
endstruc

; Program defines

width equ 80
pitch equ width + 1

%macro full_line 1
	times %1 db "X"
	db 0x0a
%endmacro

%macro hollow_line 1
	db "X"
	times %1-2 db " "
	db "X", 0x0a
%endmacro

%macro box 2
	full_line %1
	%rep %2
		hollow_line %1
	%endrep
	full_line %1
%endmacro

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .bss
	
input_char resb 1

state resb sgttyb_size
orig_flags resb 1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .data

hello_world: db "Hello World!", 0x0a
hello_world_size: equ $ - hello_world

move_up  db  0x1b, '[27A' ; Keep number in string equal to height + 2

board:
	box 80, 25
board_size equ $ - board

move_up_then_board_size equ $ - move_up

timeout:
istruc timeval
	at timeval.tv_sec,  dq 0
	at timeval.tv_nsec, dq 100000
iend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .text

global main

main:
	; disable echoing and line-buffering
	mov rax, SYS_ioctl
	mov rdi, STDIN_FILENO
	mov rsi, TIOCGETP
	mov rdx, state
	syscall

	; extract and save sg_flags
	mov ax, [state + sgttyb.sg_flags]
	mov [orig_flags], ax ; save flags 
	and ax, ~ECHO ; disable ECHO
	or ax, CBREAK ; enable CBREAK
	mov [state + sgttyb.sg_flags], ax

	; modify sg_flags
	mov rax, SYS_ioctl
	mov rdi, STDIN_FILENO
	mov rsi, TIOCSETP ; SET this time around
	mov rdx, state
	syscall

	; write initial window
	mov rax, SYS_write
	mov rdi, 1
	mov rsi, board
	mov rdx, board_size
	syscall

	; start in [40,13], moving left
	mov r14, board + 40 + 13 * pitch
	mov r15, -1
	sub r14, r15

.main_loop:
	add r14, r15 ; update snake	
	cmp byte [r14], ' ' ; crash condition
	jne .quit
	mov byte [r14], 'O' ; draw

	; write syscall (three arguments)
	mov rax, SYS_write
	mov rdi, 1
	mov rsi, move_up
	mov rdx, move_up_then_board_size
	syscall

	; Non-blocking input
	mov rax, SYS_fcntl
	mov rdi, STDIN_FILENO
	mov rsi, F_SETFL
	mov rdx, O_NONBLOCK
	syscall

	; sleep
	mov rax, SYS_select
	mov rdi, 0              ; nfds
	mov rsi, 0              ; readfds
	mov rdx, 0              ; writefds
	mov rcx, 0              ; errorfds
	mov r8, timeout         ; timeout
	syscall

.read_more
	; read keyboard input
	mov rax, SYS_read
	mov rdi, 0
	mov rsi, input_char
	mov rdx, 1
	syscall

	cmp rax, 1
    jne .done

	mov al, [input_char]

	; move snake accordingly
	cmp al, 'w'
	jne .not_up
	mov r15, -pitch
	jmp .done
.not_up:

	cmp al, 's'
	jne .not_down
	mov r15, pitch
	jmp .done
.not_down:

	cmp al, 'a'
	jne .not_left
	mov r15, -1
	jmp .done
.not_left:

	cmp al, 'd'
	jne .not_right
	mov r15, 1
	jmp .done
.not_right:

	cmp al, 'q'
	je .quit

	jmp .read_more

.done:
	; Blocking input again
	mov rax, SYS_fcntl
	mov rdi, STDIN_FILENO
	mov rsi, F_SETFL
	mov rdx, 0
	syscall	

	jmp .main_loop

.quit:
	; restore flags
	mov ax, [orig_flags]
	mov [state + sgttyb.sg_flags], ax
	; set restored state
	mov rax, SYS_ioctl
	mov rdi, STDIN_FILENO
	mov rsi, TIOCSETP
	mov rdx, state
	syscall

	; exit syscall (returns 0)
	mov rax, SYS_exit
	mov rdi, 0
	syscall
