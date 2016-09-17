	.code16

	.equ INITSEG, 0x9000
	.equ SYSSEG, 0x1000
	.equ SETUPSEG, 0x9020

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

_start:

# read cur position in 0x90000~0x90001 two byte
	mov $0x03, %ah # read cur position
	xor %bh, %bh # clean page
	int $0x10 # read my bro

	mov $INITSEG, %ax
	mov %ax, %ds
	add $0x0800, %dx # lxhuster tell me to show lines below 8
	mov %dx, %ds:0 # save cur position to 0x90000


# Get memory size (extended mem, kB) to 0x90002
	mov $0x88, %ah
	int $0x15
	mov %ax, %ds:2


# get show mode of the video card
    mov $0x0f, %ah
    int $0x10
    mov %bx, %ds:4 #bh display page
    mov %ax, %ds:6 #al indicate video mode, ah indicate window width 


# check for EGA/VGA and some config parameters
	mov $0x12, %ah
	mov $0x10, %bl
	int $0x10
	mov %ax, %ds:8
	mov %bx, %ds:10
	mov %cx, %ds:12

# Get hd0 data
	mov $0x0000, %ax
	mov %ax, %ds
	lds %ds:4*0x41, %si
	mov $INITSEG, %ax
	mov %ax, %es
	mov $0x0080, %di
	mov $0x08, %cx
	rep
	movsw

# Get hd1 data
	mov $0x0000, %ax
	mov %ax, %ds
	lds %ds:4*0x46, %si
	mov $INITSEG, %ax
	mov %ax, %es
	mov $0x0090, %di
	mov $0x08, %cx
	rep
	movsw

# query bios is there has second hd or not
	mov $0x1500, %ax
	mov $0x81, %dl # 0x80 indicate first driver, 0x81 indicate second driver
	int $0x13
	jc no_disk1
	cmp $0x03, %ah # ah = 0x03 means hd
	je is_disk1

no_disk1: # clear hd1 cache
	mov $INITSEG, %ax
	mov %ax, %es
	lds %es:4*0x46, %di
	cld # clear DF flag, means auto inc
	mov $0x10, %cx
	mov $0x00, %ax
	rep
	stosb

# we mov system to 0x0000
is_disk1:
	cli

	mov $0x00, %ax

do_move:
	mov %ax, %es
	add $0x1000, %ax
	cmp $0x9000, %ax
	jz end_move
	mov %ax, %ds
	xor %si, %si
	xor %di, %di
	cld
	mov $0x8000, %cx
	rep 
	movsw
	jmp do_move


# load gdt, idt
end_move:
	mov $SETUPSEG, %ax
	mov %ax, %ds
	lgdt gdt_48
	lidt idt_48

# that was painless, now we enable A20

	inb     $0x92, %al	# open A20 line(Fast Gate A20).
	orb     $0b00000010, %al
	outb    %al, $0x92

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.


# use two 8259 chips

#ICW1
#use A0 = 0, D4 = 1 to initial chip 
	mov	$0x10, %al		# initialization sequence(ICW1)
					# ICW4 needed(1),CASCADE mode,Level-triggered
	out	%al, $0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
	out	%al, $0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb

#ICW2
	mov	$0x20, %al		# start of hardware int's (0x20)(ICW2)
	out	%al, $0x21		# from 0x20-0x27
	.word	0x00eb,0x00eb
	mov	$0x28, %al		# start of hardware int's 2 (0x28)
	out	%al, $0xA1		# from 0x28-0x2F
	.word	0x00eb,0x00eb		#               IR 7654 3210

#ICW3 identify master or slave
	mov	$0x04, %al		# 8259-1 is master(0000 0100) --\
	out	%al, $0x21		#				|
	.word	0x00eb,0x00eb		#			 INT	/
	mov	$0x02, %al		# 8259-2 is slave(       010 --> 2)
	out	%al, $0xA1
	.word	0x00eb,0x00eb

#ICW4
	mov	$0x01, %al		# 8086 mode for both
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1
	.word	0x00eb,0x00eb

#mask all int
	mov	$0xFF, %al		# mask off all interrupts for now
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1


# we get into vitual mode
	mov %cr0, %eax # the cr0 regist is 32bit
	bts $0, %ax # set pe bit in cr0 to get in protect mode
	mov %eax, %cr0


# jmp to head.s
				# segment-descriptor        (INDEX:TI:RPL)
	.equ	sel_cs0, 0x0008 # select for code segment 0 (  001:0 :00) 
	ljmp	$sel_cs0, $0	# jmp offset 0 of code segment 0 in gdt

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	$0x64, %al	# 8042 status port
	test	$2, %al		# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret

# total 3 table
gdt_table:
	.word 0, 0, 0, 0 # this table no use

# code seg descriptor
	.word 0x07ff # seg limit 8m
	.word 0x0000 # code seg base addr
	.word 0x9A00 # code seg can read and exec
	.word 0x00C0 # set seg limit mode

# data seg descriptor
	.word 0x07ff # seg limit 8m
	.word 0x0000
	.word 0x9200 # data seg can read write
	.word 0x00C0 # set seg limit mode


idt_48:
	.word 0x00
	.word 0x00, 0x00

gdt_48:
	.word 0x800 # limit 256 num of descriptor
	.word gdt_table+512, 0x9

	
.text
endtext:
.data
enddata:
.bss
endbss:
