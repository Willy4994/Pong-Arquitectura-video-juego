# Makefile for Pong Bare-Metal on Raspberry Pi Pico (RP2040)
# 100% ARM Assembly (ARMv6-M Cortex-M0+)

TOOLCHAIN ?= C:/Users/cachi/arm-toolchain/arm-gnu-toolchain-13.3.rel1-mingw-w64-i686-arm-none-eabi/bin/arm-none-eabi-
AS        := $(TOOLCHAIN)as
LD        := $(TOOLCHAIN)ld
OBJCOPY   := $(TOOLCHAIN)objcopy
OBJDUMP   := $(TOOLCHAIN)objdump
PYTHON    ?= python

ASFLAGS   := -mcpu=cortex-m0plus -mthumb
LDFLAGS   := -T memmap.ld

OBJS      := boot2.o crt0.o system.o timer.o inputs.o video.o font.o main.o

all: pong.uf2

%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

pong.elf: $(OBJS) memmap.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

pong.bin: pong.elf
	$(OBJCOPY) -O binary $< $@

pong.uf2: pong.bin uf2conv.py
	$(PYTHON) uf2conv.py $< $@

flash: pong.uf2
	@if exist D:\ ( \
		echo Flashing to D:\... && \
		copy pong.uf2 D:\ \
	) else ( \
		echo Drive D: not found. Put Pico in BOOTSEL mode. \
	)

clean:
	rm -f *.o *.elf *.bin *.uf2

.PHONY: all clean flash
