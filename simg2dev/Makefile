SRC = simg2dev
LIB = libsparse

PWD = $(shell pwd)

EXTRA_CFLAGS  := -Wall -O3 -fomit-frame-pointer
EXTRA_CFLAGS  += -I$(PWD)/libsparse/include

EXTRA_LDFLAGS :=

LIBS := $(PWD)/libsparse/libsparse.a

PHONY := all clean
all: lib src

PHONY += lib
lib:
	@for dir in $(LIB); do \
		make \
		EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
		EXTRA_LDFLAGS="$(EXTRA_LDFLAGS)" \
		LIBS="$(LIBS)" \
		-C $$dir || exit $?; \
        done

PHONY += src
src:
	@for dir in $(SRC); do \
		make \
		EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
		EXTRA_LDFLAGS="$(EXTRA_LDFLAGS)" \
		LIBS="$(LIBS)" \
		-C $$dir || exit $?; \
        done

clean:
	@for dir in $(SRC); do \
                make -C $$dir clean || exit $?; \
        done
	@for dir in $(LIB); do \
                make -C $$dir clean || exit $?; \
        done

.PHONY: $(PHONY)
