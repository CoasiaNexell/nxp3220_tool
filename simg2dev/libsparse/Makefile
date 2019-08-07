CC := $(CROSS_COMPILE)gcc
AR := $(CROSS_COMPILE)ar

CFLAGS  := $(EXTRA_CFLAGS)
CFLAGS  += -Iinclude
ARFLAGS	:= crv

COBJS	:= backed_block.o sparse.o sparse_err.o \
	   output_file.o sparse_crc32.o sparse_read.o

OBJS	:= $(COBJS)

TARGET = libsparse

all : $(TARGET)

$(TARGET) : depend $(OBJS)
	$(AR) $(ARFLAGS) $(TARGET).a $(OBJS)

.PHONY: clean

clean :
	rm -rf $(OBJS) $(TARGET) core .depend *.a

ifeq (.depend,$(wildcard .depend))
include .depend
endif

depend dep:
	$(CC) -M $(CFLAGS) $(COBJS:.o=.c) > .depend

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDE) -c -o $@ $<
