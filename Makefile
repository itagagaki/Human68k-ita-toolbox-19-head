# Makefile for ITA TOOLBOX #? head

AS	= \usr\pds\HAS.X -l -i $(INCLUDE)
LK	= \usr\pds\hlk.x -x
CV      = -\bin\CV.X -r
INSTALL = cp -up
BACKUP  = cp -au
CP      = cp
RM      = -rm -f

INCLUDE = $(HOME)/fish/include

DESTDIR   = A:/usr/ita
BACKUPDIR = B:/head/1.0

EXTLIB = $(HOME)/fish/lib/ita.l

###

PROGRAM = head.x

###

.PHONY: all clean clobber install backup

.TERMINAL: *.h *.s

%.r : %.x	; $(CV) $<
%.x : %.o	; $(LK) $< $(EXTLIB)
%.o : %.s	; $(AS) $<

###

all:: $(PROGRAM)

clean::

clobber:: clean
	$(RM) *.bak *.$$* *.o *.x

###

$(PROGRAM) : $(INCLUDE)/doscall.h $(INCLUDE)/chrcode.h $(EXTLIB)

install::
	$(INSTALL) $(PROGRAM) $(DESTDIR)

backup::
	fish -fc '$(BACKUP) * $(BACKUPDIR)'

clean::
	$(RM) $(PROGRAM)

###
