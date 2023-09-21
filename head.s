* head - output head of input
*
* Itagaki Fumihiko 28-Jan-93  Create.
* 1.0
* Itagaki Fumihiko 02-Feb-93  count がバイト単位で出力がブロック・デバイスのときに
*                             ヘッダが出力されないバグを修正．
* 1.1
* Itagaki Fumihiko 06-Feb-93  ファイル引数に過剰な / があれば除去する
* Itagaki Fumihiko 06-Feb-93  bsr tfopen -> DOS _OPEN
* Itagaki Fumihiko 06-Feb-93  bsr fclose -> DOS _CLOSE
* Itagaki Fumihiko 06-Feb-93  bsr mulul -> lsl.l
* 1.2
* Itagaki Fumihiko 09-Feb-93  head_byte で _WRITE の診断を忘れていた
* 1.3
* Itagaki Fumihiko 19-Feb-93  標準入力が切り替えられていても端末から^Cや^Sなどが効くようにした
* Itagaki Fumihiko 19-Feb-93  標準入力は先頭にシークしてから処理する
* 1.4
* Itagaki Fumihiko 18-Sep-94  たとえば -5c で端末から ab^Z を入力したとき ^Z が EOF として認識
*                             されないバグを修正.
* 1.5
*
* Usage: head [ -qvBCZ ] { [ -<N>[ckl] ] [ -- ] [ <ファイル> ] } ...

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref isdigit
.xref atou
.xref strlen
.xref strfor1
.xref strip_excessive_slashes

STACKSIZE	equ	2048

INPBUF_SIZE	equ	8192
OUTBUF_SIZE	equ	8192

DEFAULT_COUNT	equ	10

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_q		equ	0	*  -q
FLAG_v		equ	1	*  -v
FLAG_B		equ	2	*  -B
FLAG_C		equ	3	*  -C
FLAG_Z		equ	4	*  -Z
FLAG_byte_unit	equ	5

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		moveq	#0,d6				*  D6.W : エラー・コード
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.B : フラグ
		move.l	#DEFAULT_COUNT,count
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		move.b	1(a0),d0
		beq	decode_opt_done

		bsr	isdigit
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		cmp.b	#'q',d0
		beq	option_q_found

		cmp.b	#'v',d0
		beq	option_v_found

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

option_q_found:
		bset	#FLAG_q,d5
		bclr	#FLAG_v,d5
		bra	set_option_done

option_v_found:
		bset	#FLAG_v,d5
		bclr	#FLAG_q,d5
		bra	set_option_done

option_B_found:
		bset	#FLAG_B,d5
		bclr	#FLAG_C,d5
		bra	set_option_done

option_C_found:
		bset	#FLAG_C,d5
		bclr	#FLAG_B,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering
		beq	stdout_is_block_device		*  -- ブロック・デバイスである
	*
	*  出力はキャラクタ・デバイス
	*
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	outbuf_ok

		btst	#FLAG_B,d5
		bne	outbuf_ok

		bset	#FLAG_C,d5
		bra	outbuf_ok

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
outbuf_ok:
		bsr	parse_count
		lea	msg_header2(pc),a1
		st	show_header
		btst	#FLAG_v,d5
		bne	do_files

		sf	show_header
		btst	#FLAG_q,d5
		bne	do_files

		cmp.l	#1,d7
		shi	show_header
do_files:
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin
		bmi	start_do_files

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
start_do_files:
	*
	*  開始
	*
		tst.l	d7
		beq	do_stdin
for_file_loop:
		subq.l	#1,d7
		movea.l	a0,a3
		bsr	strfor1
		exg	a0,a3
		cmpi.b	#'-',(a0)
		bne	do_file

		tst.b	1(a0)
		bne	do_file
do_stdin:
		lea	msg_stdin(pc),a0
		move.l	stdin,d1
		bmi	open_fail

		clr.w	-(a7)				*  先頭
		clr.l	-(a7)				*  +0に
		move.w	d1,-(a7)			*  標準入力を
		DOS	_SEEK				*  シーク
		addq.l	#8,a7
		bsr	head_one
		bra	for_file_continue

do_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		move.l	d0,d1
		bmi	open_fail

		bsr	head_one
		move.w	d1,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
for_file_continue:
		movea.l	a3,a0
		bsr	parse_count
		tst.l	d7
		beq	all_done

		lea	msg_header1(pc),a1
		bra	for_file_loop

all_done:
exit_program:
		move.l	stdin,d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

open_fail:
		lea	msg_open_fail(pc),a2
		bra	werror_exit_2
****************************************************************
parse_count:
parse_count_loop:
		tst.l	d7
		beq	parse_count_done

		cmpi.b	#'-',(a0)
		bne	parse_count_done

		subq.l	#1,d7
		addq.l	#1,a0
		cmpi.b	#'-',(a0)
		bne	parse_count_1

		tst.b	1(a0)
		bne	parse_count_break

		addq.l	#2,a0
		bra	parse_count_done

parse_count_1:
		bsr	atou
		bmi	parse_count_break
		bne	bad_count

		move.l	d1,count
		bclr	#FLAG_byte_unit,d5
		move.b	(a0),d0
		beq	parse_count_continue

		cmp.b	#'l',d0
		beq	parse_count_unit_ok

		bset	#FLAG_byte_unit,d5
		cmp.b	#'c',d0
		beq	parse_count_unit_ok

		cmp.b	#'k',d0
		bne	bad_count

		cmp.l	#$400000,d1
		bhs	bad_count

		lsl.l	#8,d1
		lsl.l	#2,d1
		move.l	d1,count
parse_count_unit_ok:
		addq.l	#1,a0
parse_count_continue:
		tst.b	(a0)+
		beq	parse_count_loop
bad_count:
		lea	msg_illegal_count(pc),a0
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

parse_count_break:
		subq.l	#1,a0
		addq.l	#1,d7
parse_count_done:
		rts
****************************************************************
* head_one
****************************************************************
STAT_EOF		equ	0
STAT_CR			equ	1

head_one:
		tst.b	show_header
		beq	head_one_1

		move.l	a0,-(a7)
		movea.l	a1,a0
		bsr	puts
		movea.l	(a7),a0
		bsr	puts
		lea	msg_header3(pc),a0
		bsr	puts
		movea.l	(a7)+,a0
head_one_1:
		move.l	count,d2			*  D2.L : 書き出しカウント
		beq	head_one_return

		moveq	#0,d3				*  D3.L : bit0 - EOF
							*         bit1 - pending CR
		btst	#FLAG_Z,d5
		sne	ignore_from_ctrlz
		sf	ignore_from_ctrld
		move.w	d1,d0
		bsr	is_chrdev
		beq	head_one_2			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	head_one_2

		st	ignore_from_ctrlz
		st	ignore_from_ctrld
head_one_2:
head_loop:
		btst	#STAT_EOF,d3
		bne	head_one_done

		move.l	#INPBUF_SIZE,-(a7)
		pea	inpbuf(pc)
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
		beq	head_one_done

		lea	inpbuf(pc),a2
		btst	#FLAG_byte_unit,d5
		bne	head_byte
output_lines:
		move.b	(a2)+,d0
		cmp.b	#LF,d0
		bne	output_lines_putc

		btst	#FLAG_C,d5
		beq	output_lines_putc

		bset	#STAT_CR,d3			*  LFの前にCRを吐かせるため
output_lines_putc:
		bsr	flush_cr
		bset	#STAT_CR,d3
		cmp.b	#CR,d0
		beq	output_lines_continue

		bclr	#STAT_CR,d3
		bsr	putc
		cmp.b	#LF,d0
		bne	output_lines_continue

		subq.l	#1,d2
		beq	head_one_done
output_lines_continue:
		subq.l	#1,d4
		bne	output_lines
		bra	head_loop

head_one_done:
		bsr	flush_cr
head_one_return:
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering
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
		blo	write_fail

		movea.l	a4,a5
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
flush_done:
		move.l	(a7)+,d0
		rts

head_byte:
		bsr	flush_outbuf
		cmp.l	d2,d4
		bls	head_byte_1

		move.l	d2,d4
head_byte_1:
		move.l	d4,-(a7)
		pea	inpbuf(pc)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	d4,d0
		blo	write_fail

		sub.l	d4,d2
		bne	head_loop

		rts

read_fail:
		bsr	flush_outbuf
		lea	msg_read_fail(pc),a2
werror_exit_2:
		bsr	werror_myname_and_msg
		movea.l	a2,a0
		bsr	werror
		moveq	#2,d6
		bra	exit_program
*****************************************************************
flush_cr:
		btst	#STAT_CR,d3
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

		movem.l	d1/a0-a1,-(a7)
		lea	inpbuf(pc),a0
		movea.l	a0,a1
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
		sub.l	a1,d4
		bset	#STAT_EOF,d3
trunc_done:
		movem.l	(a7)+,d1/a0-a1
trunc_return:
		rts
*****************************************************************
putc:
		tst.b	do_buffering
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
	dc.b	'## head 1.5 ##  Copyright(C)1993-94 by Itagaki Fumihiko',0

msg_myname:		dc.b	'head: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'head: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_illegal_count:	dc.b	'カウントの指定が不正です',0
msg_header1:		dc.b	CR,LF
msg_header2:		dc.b	'==> ',0
msg_header3:		dc.b	' <=='
msg_newline:		dc.b	CR,LF,0
msg_usage:		dc.b	CR,LF,'使用法:  head [-qvBCZ] { [-<N>[ckl]] [--] [<ファイル>] } ...',CR,LF,0
*****************************************************************
.bss

.even
stdin:			ds.l	1
outbuf_free:		ds.l	1
count:			ds.l	1
show_header:		ds.b	1
ignore_from_ctrlz:	ds.b	1
ignore_from_ctrld:	ds.b	1
do_buffering:		ds.b	1
inpbuf:			ds.b	INPBUF_SIZE

		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
