.code16

.equ SYSSIZE, 0x3000 #196kb kernel

.global _start, begtext, endtext, begbss, endbss, begdata, enddata

.text
begtext:
.data
begdata:
.bss
begbss:

.text

# define constant val
.equ SETUPLEN, 4
.equ BOOTSEG, 0x07c0
.equ INITSEG, 0x9000
.equ SETUPSEG, 0x9020
.equ SYSSEG, 0x1000
.equ ENDSEG, SYSSEG + SYSSIZE

# first hd, first partion
.equ ROOT_DEV, 0x301

_start:
# set source address
	mov $BOOTSEG, %ax
	mov %ax, %ds
	xor %si, %si

# set dest address
	mov $INITSEG, %ax
	mov %ax, %es
	xor %di, %di

# set need copy num 512 byte
	mov $256, %cx

# copy bootsec to 0x9000
	rep
	movsw
	ljmp $INITSEG, $go


# this is not my code
go:	mov	%cs, %ax
mov	%ax, %ds
mov	%ax, %es
# put stack at 0x9ff00.
mov	%ax, %ss
mov	$0xFF00, %sp		# arbitrary value >>512

# load the setup-sectors directly after the bootblock.
# Note that 'es' is already set up.

load_setup:
mov	$0x0000, %dx		# drive 0, head 0
mov	$0x0002, %cx		# sector 2, track 0
mov	$0x0200, %bx		# address = 512, in INITSEG
.equ    AX, 0x0200+SETUPLEN
mov     $AX, %ax		# service 2, nr of sectors
int	$0x13			# read it
jnc	ok_load_setup		# ok - continue
mov	$0x0000, %dx
mov	$0x0000, %ax		# reset the diskette
int	$0x13
jmp	load_setup

ok_load_setup:

# Get disk drive parameters, specifically nr of sectors/track

mov	$0x00, %dl
mov	$0x0800, %ax		# AH=8 is get drive parameters
int	$0x13
mov	$0x00, %ch
#seg cs
mov	%cx, %cs:sectors+0	# %cs means sectors is in %cs
mov	$INITSEG, %ax
mov	%ax, %es

# Print some inane message

mov	$0x03, %ah		# read cursor pos
xor	%bh, %bh
int	$0x10

mov	$33, %cx
mov	$0x0007, %bx		# page 0, attribute 7 (normal)
#lea	msg1, %bp
mov     $msg1, %bp
mov	$0x1301, %ax		# write string, move cursor
int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

mov	$SYSSEG, %ax
mov	%ax, %es		# segment of 0x010000
call	read_it
call	kill_motor

# After that we check which root-device to use. If the device is
# defined (#= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

#seg cs
mov	%cs:root_dev+0, %ax
cmp	$0, %ax
jne	root_defined
#seg cs
mov	%cs:sectors+0, %bx
mov	$0x0208, %ax		# /dev/ps0 - 1.2Mb
cmp	$15, %bx
je	root_defined
mov	$0x021c, %ax		# /dev/PS0 - 1.44Mb
cmp	$18, %bx
je	root_defined
undef_root:
jmp undef_root
root_defined:
#seg cs
mov	%ax, %cs:root_dev+0

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

ljmp	$SETUPSEG, $0

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
sread:	.word 1+ SETUPLEN	# sectors read of current track
head:	.word 0			# current head
track:	.word 0			# current track

read_it:
mov	%es, %ax
test	$0x0fff, %ax
die:	jne 	die			# es must be at 64kB boundary
xor 	%bx, %bx		# bx is starting address within segment
rp_read:
mov 	%es, %ax
cmp 	$ENDSEG, %ax		# have we loaded all yet?
jb	ok1_read
ret
ok1_read:
#seg cs
mov	%cs:sectors+0, %ax
sub	sread, %ax
mov	%ax, %cx
shl	$9, %cx
add	%bx, %cx
jnc 	ok2_read
je 	ok2_read
xor 	%ax, %ax
sub 	%bx, %ax
shr 	$9, %ax
ok2_read:
call 	read_track
mov 	%ax, %cx
add 	sread, %ax
#seg cs
cmp 	%cs:sectors+0, %ax
jne 	ok3_read
mov 	$1, %ax
sub 	head, %ax
jne 	ok4_read
incw    track
ok4_read:
mov	%ax, head
xor	%ax, %ax
ok3_read:
mov	%ax, sread
shl	$9, %cx
add	%cx, %bx
jnc	rp_read
mov	%es, %ax
add	$0x1000, %ax
mov	%ax, %es
xor	%bx, %bx
jmp	rp_read

read_track:
push	%ax
push	%bx
push	%cx
push	%dx
mov	track, %dx
mov	sread, %cx
inc	%cx
mov	%dl, %ch
mov	head, %dx
mov	%dl, %dh
mov	$0, %dl
and	$0x0100, %dx
mov	$2, %ah
int	$0x13
jc	bad_rt
pop	%dx
pop	%cx
pop	%bx
pop	%ax
ret
bad_rt:	mov	$0, %ax
mov	$0, %dx
int	$0x13
pop	%dx
pop	%cx
pop	%bx
pop	%ax
jmp	read_track

#/*
# * This procedure turns off the floppy drive motor, so
# * that we enter the kernel in a known state, and
# * don't have to worry about it later.
# */
kill_motor:
push	%dx
mov	$0x3f2, %dx
mov	$0, %al
outsb
pop	%dx
ret

sectors:
.word 0

msg1:
.byte 13,10
.ascii "Loading lxhuster ( ^_^ ) .."
.byte 13,10,13,10

.org 508
root_dev:
.word ROOT_DEV
boot_flag:
.word 0xAA55




.text
endtext:
.data
enddata:
.bss
endbss:
