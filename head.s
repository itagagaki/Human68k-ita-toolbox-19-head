* head - conheadinate
*
* Itagaki Fumihiko 13-Aug-92  Create.
*
* Usage: head [ -FZh ] [ -<行数> ] [ <ファイル> [ -<行数> ] ] ...

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref isdigit
.xref atou
.xref strlen
.xref strfor1
.xref tfopen
.xref fclose

STACKSIZE	equ	512

INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED	equ	8192
OUTBUF_SIZE	equ	1024

DEFAULT_COUNT	equ	10

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_nocook	equ	0	*  -F
FLAG_ctrlz	equ	1	*  -Z
FLAG_h		equ	2	*  -h
FLAG_buffering	equ	3	*  （出力がブロック・デバイスのときON）
FLAG_nl		equ	4	*  改行コードを変換する（出力がキャラクタ・デバイスのときON）


.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		DOS	_GETPDB
		movea.l	d0,a0				*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#DEFAULT_COUNT,count
		moveq	#0,d6				*  D6.W : エラー・コード
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
		bsr	DecodeHUPAIR			*  デコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
	*
	*  オプションを解釈する
	*
		moveq	#0,d5				*  D5.B : フラグ
parse_option:
		tst.l	d7
		beq	parse_option_done

		cmpi.b	#'-',(a0)
		bne	parse_option_done

		move.b	1(a0),d0
		bsr	isdigit
		beq	parse_option_done

		addq.l	#1,a0
		subq.l	#1,d7
parse_option_arg:
		move.b	(a0)+,d0
		beq	parse_option

		moveq	#FLAG_nocook,d1
		cmp.b	#'F',d0
		beq	option_found

		moveq	#FLAG_ctrlz,d1
		cmp.b	#'Z',d0
		beq	option_found

		moveq	#FLAG_h,d1
		cmp.b	#'h',d0
		beq	option_found

		move.w	d0,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

option_found:
		bset	d1,d5
		bra	parse_option_arg

parse_option_done:
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		beq	stdout_is_block_device		*  -- ブロック・デバイスである
		*
		*  出力はキャラクタ・デバイス
		*
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	malloc_max_for_input

		move.l	#INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED,d0
		btst	#FLAG_nocook,d5
		bne	malloc_inpbuf

		bset	#FLAG_nl,d5
		bra	malloc_inpbuf

stdout_is_block_device:
		*
		*  stdoutはブロック・デバイス
		*
		*  出力バッファを確保する
		*
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a4				*  A4 : 出力バッファの先頭アドレス
		movea.l	d0,a5				*  A5 : 出力バッファのポインタ
		bset	#FLAG_buffering,d5
malloc_max_for_input:
		move.l	#$00ffffff,d0
malloc_inpbuf:
		*  入力バッファを確保する
		move.l	d0,inpbuf_size
		bsr	malloc
		bpl	inpbuf_ok

		sub.l	#$81000000,d0
		move.l	d0,inpbuf_size
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		movea.l	d0,a3				*  A3 : 入力バッファの先頭アドレス
		bsr	parse_count
		cmp.l	#1,d7
		blo	do_stdin

		lea	msg_header2(pc),a1
		shi	show_header
		btst	#FLAG_h,d5
		beq	for_file_loop

		sf	show_header
for_file_loop:
		lea	msg_open_fail(pc),a2
		moveq	#0,d0
		bsr	tfopen
		bmi	werror_exit_2

		move.w	d0,d1
		sf	this_is_stdin
		tst.b	show_header
		beq	do_file_do

		move.l	a0,-(a7)
		movea.l	a1,a0
		bsr	puts
		movea.l	(a7),a0
		bsr	puts
		lea	msg_header3(pc),a0
		bsr	puts
		movea.l	(a7)+,a0
do_file_do:
		bsr	dofile
		move.w	d1,d0
		bsr	fclose
		bsr	strfor1
		subq.l	#1,d7
		bsr	parse_count
		tst.l	d7
		beq	all_done

		lea	msg_header1(pc),a1
		bra	for_file_loop

do_stdin:
		moveq	#0,d1
		st	this_is_stdin
		bsr	dofile
all_done:
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2
****************************************************************
parse_count:
		tst.l	d7
		beq	parse_count_done
parse_count_loop:
		cmpi.b	#'-',(a0)
		bne	parse_count_done

		addq.l	#1,a0
		bsr	atou
		bmi	parse_count_break
		bne	bad_count

		tst.b	(a0)+
		bne	bad_count

		move.l	d1,count
		subq.l	#1,d7
		bne	parse_count_loop
parse_count_done:
		rts

parse_count_break:
		subq.l	#1,a0
		rts

bad_count:
		lea	msg_illegal_count(pc),a0
		bsr	werror_myname_and_msg
		bra	usage
****************************************************************
* dofile
****************************************************************
STAT_EOF		equ	0
STAT_CR			equ	1

dofile:
		tst.l	count
		beq	dofile_return

		moveq	#0,d2				*  D2.L : 行番号
		moveq	#0,d3				*  D3.L : bit0 - EOF
							*         bit1 - pending CR
		btst	#FLAG_ctrlz,d5
		sne	ignore_from_ctrlz
		sf	ignore_from_ctrld
		move.w	d1,d0
		bsr	is_chrdev
		beq	dofile_2			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	dofile_2

		st	ignore_from_ctrlz
		st	ignore_from_ctrld
dofile_2:
dofile_loop:
		move.l	inpbuf_size,-(a7)
		move.l	a3,-(a7)
		move.w	d1,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d4				*  D4.L : バッファに読み込んだバイト数
		bmi	read_fail

		tst.b	ignore_from_ctrlz
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	ignore_from_ctrld
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		tst.l	d4
		beq	dofile_done

		movea.l	a3,a2
write_loop:
		move.b	(a2)+,d0
		cmp.b	#LF,d0
		bne	dofile_putc

		btst	#FLAG_nl,d5
		beq	dofile_putc

		bset	#1,d3				*  LFの前にCRを吐かせるため
dofile_putc:
		bsr	flush_cr
		bset	#1,d3
		cmp.b	#CR,d0
		beq	dofile_write_continue

		bclr	#1,d3
		bsr	putc
		cmp.b	#LF,d0
		bne	dofile_write_continue

		addq.l	#1,d2
		cmp.l	count,d2
		bhs	dofile_done
dofile_write_continue:
		subq.l	#1,d4
		bne	write_loop
dofile_continue:
		btst	#0,d3
		beq	dofile_loop
dofile_done:
		bsr	flush_cr
dofile_return:
flush_outbuf:
		move.l	d0,-(a7)
		btst	#FLAG_buffering,d5
		beq	flush_done

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free,d0
		beq	flush_done

		move.l	d0,-(a7)
		move.l	a4,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blt	write_fail

		movea.l	a4,a5
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
flush_done:
		move.l	(a7)+,d0
		rts

read_fail:
		bsr	flush_outbuf
		move.l	a0,-(a7)
		tst.b	this_is_stdin
		beq	read_fail_1

		lea	msg_stdin(pc),a0
read_fail_1:
		lea	msg_read_fail(pc),a2
werror_exit_2:
		bsr	werror_myname_and_msg
		movea.l	a2,a0
		bsr	werror
		moveq	#2,d6
		bra	exit_program
*****************************************************************
flush_cr:
		btst	#1,d3
		beq	flush_cr_return

		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		move.l	(a7)+,d0
flush_cr_return:
		rts
*****************************************************************
trunc:
		tst.l	d4
		beq	trunc_return

		movem.l	d1/a0,-(a7)
		movea.l	a3,a0
		move.l	d4,d1
trunc_find_loop:
		cmp.b	(a0)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		subq.l	#1,a0
		move.l	a0,d4
		sub.l	a3,d4
		bset	#0,d3				*  set EOF
trunc_done:
		movem.l	(a7)+,d1/a0
trunc_return:
		rts
*****************************************************************
putc:
		btst	#FLAG_buffering,d5
		bne	putc_do_buffering

		move.l	d0,-(a7)

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail

		move.l	(a7)+,d0
		bra	putc_done

putc_do_buffering:
		tst.l	outbuf_free
		bne	putc_do_buffering_1

		bsr	flush_outbuf
putc_do_buffering_1:
		move.b	d0,(a5)+
		subq.l	#1,outbuf_free
putc_done:
		rts
*****************************************************************
puts:
		movem.l	d0/a0,-(a7)
puts_loop:
		move.b	(a0)+,d0
		beq	puts_done

		bsr	putc
		bra	puts_loop
puts_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
write_fail:
		lea	msg_write_fail(pc),a0
		bsr	werror
		bra	exit_3
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
exit_3:
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## head 1.0 ##  Copyright(C)1992 by Itagaki Fumihiko',0

msg_myname:		dc.b	'head: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'head: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'(標準入力)',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_illegal_count:	dc.b	'行数が不正です',0
msg_header1:		dc.b	CR,LF
msg_header2:		dc.b	'==> ',0
msg_header3:		dc.b	' <=='
msg_newline:		dc.b	CR,LF,0
msg_usage:		dc.b	CR,LF,'使用法:  head [-FZh] [-<行数>] [ <ファイル> [-<行数>] ] ...',CR,LF,0
*****************************************************************
.bss

.even
inpbuf_size:		ds.l	1
outbuf_free:		ds.l	1
count:			ds.l	1
show_header:		ds.b	1
this_is_stdin:		ds.b	1
ignore_from_ctrlz:	ds.b	1
ignore_from_ctrld:	ds.b	1

		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
