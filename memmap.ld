/* Linker Script for RP2040 Bare-Metal Assembly */

MEMORY
{
    FLASH (rx) : ORIGIN = 0x10000000, LENGTH = 2048K
    RAM   (rwx): ORIGIN = 0x20000000, LENGTH = 264K
}

ENTRY(Reset_Handler)

SECTIONS
{
    /* Second stage bootloader at the start of flash (first 256 bytes) */
    .boot2 :
    {
        __boot2_start__ = .;
        KEEP(*(.boot2))
        . = ALIGN(256);
        __boot2_end__ = .;
    } > FLASH

    /* ARM Cortex-M0+ Vector Table, aligned to 256 bytes for VTOR */
    .vectors :
    {
        . = ALIGN(256);
        __vectors_start__ = .;
        KEEP(*(.vectors))
        __vectors_end__ = .;
    } > FLASH

    /* Code and constant data */
    .text :
    {
        . = ALIGN(4);
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
        __etext = .;
    } > FLASH

    /* Initialized data (stored in FLASH, copied to RAM at startup) */
    .data : AT (__etext)
    {
        . = ALIGN(4);
        __data_start__ = .;
        *(.data*)
        . = ALIGN(4);
        __data_end__ = .;
    } > RAM

    __data_load__ = LOADADDR(.data);

    /* Uninitialized data (zeroed at startup in RAM) */
    .bss :
    {
        . = ALIGN(4);
        __bss_start__ = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > RAM

    /* Top of RAM used as initial Stack Pointer */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

