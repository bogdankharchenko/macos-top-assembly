# Makefile for ARM64 macOS assembly top clone

TOP = top_asm
AS = as
LD = ld
CC = cc

ASFLAGS = -arch arm64
LDFLAGS = -arch arm64 -lSystem -syslibroot $(shell xcrun --show-sdk-path) -e _main

.PHONY: all clean verify

all: $(TOP)

$(TOP): top.o
	$(LD) $(LDFLAGS) -o $@ $<

top.o: top.s
	$(AS) $(ASFLAGS) -o $@ $<

verify: verify_offsets.c
	$(CC) -o verify_offsets $<
	./verify_offsets

clean:
	rm -f top.o $(TOP) verify_offsets
