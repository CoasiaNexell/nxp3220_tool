CC := $(CROSS_COMPILE)gcc

CFLAGS  := $(EXTRA_CFLAGS)

LDFLAGS := $(EXTRA_LDFLAGS)
LDFLAGS += -static

COBJS	:= simg2dev.o

OBJS	:= $(COBJS) $(CPPOBJS)

TARGET = simg2dev

all : $(TARGET)

$(TARGET) : depend $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LIBS)

.PHONY: clean

clean :
	rm -rf $(OBJS) $(TARGET) core .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif

depend dep:
	$(CC)  -M $(CFLAGS) $(COBJS:.o=.c) > .depend

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDE) -c -o $@ $<
