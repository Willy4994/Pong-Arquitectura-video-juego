/*
 * crt0.s - Startup code, Vector Table, and Low-Level Handlers for RP2040
 * Architecture: ARMv6-M (Cortex-M0+)
 * Pure Assembly - Bare Metal (No SDK, No Arduino)
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global Reset_Handler
    .global Default_Handler
    .global TIMER_IRQ_0_Handler

    /* External symbols from linker script */
    .extern __stack_top
    .extern __vectors_start__
    .extern __etext
    .extern __data_start__
    .extern __data_end__
    .extern __data_load__
    .extern __bss_start__
    .extern __bss_end__
    .extern main

/* ============================================================================
 * Cortex-M0+ Vector Table
 * Must be aligned to 256 bytes for RP2040 VTOR
 * ============================================================================ */
    .section .vectors, "ax"
    .align 8
vector_table:
    .word   __stack_top         /* 0: Initial Stack Pointer */
    .word   Reset_Handler       /* 1: Reset Handler */
    .word   NMI_Handler         /* 2: NMI Handler */
    .word   HardFault_Handler   /* 3: HardFault Handler */
    .word   0                   /* 4: Reserved */
    .word   0                   /* 5: Reserved */
    .word   0                   /* 6: Reserved */
    .word   0                   /* 7: Reserved */
    .word   0                   /* 8: Reserved */
    .word   0                   /* 9: Reserved */
    .word   0                   /* 10: Reserved */
    .word   SVC_Handler         /* 11: SVCall */
    .word   0                   /* 12: Reserved */
    .word   0                   /* 13: Reserved */
    .word   PendSV_Handler      /* 14: PendSV */
    .word   SysTick_Handler     /* 15: SysTick */

    /* External Interrupts (RP2040 IRQ 0..31) */
    .word   TIMER_IRQ_0_Handler /* IRQ 0: TIMER_IRQ_0 (Hardware Timer) */
    .word   Default_Handler     /* IRQ 1: TIMER_IRQ_1 */
    .word   Default_Handler     /* IRQ 2: TIMER_IRQ_2 */
    .word   Default_Handler     /* IRQ 3: TIMER_IRQ_3 */
    .word   Default_Handler     /* IRQ 4: PWM_IRQ_WRAP */
    .word   Default_Handler     /* IRQ 5: USBCTRL_IRQ */
    .word   Default_Handler     /* IRQ 6: XIP_IRQ */
    .word   Default_Handler     /* IRQ 7: PIO0_IRQ_0 */
    .word   Default_Handler     /* IRQ 8: PIO0_IRQ_1 */
    .word   Default_Handler     /* IRQ 9: PIO1_IRQ_0 */
    .word   Default_Handler     /* IRQ 10: PIO1_IRQ_1 */
    .word   Default_Handler     /* IRQ 11: DMA_IRQ_0 */
    .word   Default_Handler     /* IRQ 12: DMA_IRQ_1 */
    .word   Default_Handler     /* IRQ 13: IO_IRQ_BANK0 */
    .word   Default_Handler     /* IRQ 14: IO_IRQ_QSPI */
    .word   Default_Handler     /* IRQ 15: SIO_IRQ_PROC0 */
    .word   Default_Handler     /* IRQ 16: SIO_IRQ_PROC1 */
    .word   Default_Handler     /* IRQ 17: CLOCKS_IRQ */
    .word   Default_Handler     /* IRQ 18: SPI0_IRQ */
    .word   Default_Handler     /* IRQ 19: SPI1_IRQ */
    .word   Default_Handler     /* IRQ 20: UART0_IRQ */
    .word   Default_Handler     /* IRQ 21: UART1_IRQ */
    .word   Default_Handler     /* IRQ 22: ADC_IRQ_FIFO */
    .word   Default_Handler     /* IRQ 23: I2C0_IRQ */
    .word   Default_Handler     /* IRQ 24: I2C1_IRQ */
    .word   Default_Handler     /* IRQ 25: RTC_IRQ */
    .word   Default_Handler     /* IRQ 26: Reserved */
    .word   Default_Handler     /* IRQ 27: Reserved */
    .word   Default_Handler     /* IRQ 28: Reserved */
    .word   Default_Handler     /* IRQ 29: Reserved */
    .word   Default_Handler     /* IRQ 30: Reserved */
    .word   Default_Handler     /* IRQ 31: Reserved */

/* ============================================================================
 * Reset Handler
 * Called immediately upon CPU boot / exit from boot2
 * ============================================================================ */
    .section .text
    .thumb_func
Reset_Handler:
    /* Step 1: Configure VTOR (Vector Table Offset Register) in Cortex-M0+ PPB
     * PPB Base: 0xE000ED00, VTOR offset: 0x08 -> Address: 0xE000ED08
     */
    ldr     r0, =0xE000ED08
    ldr     r1, =__vectors_start__
    str     r1, [r0]

    /* Step 2: Copy initialized data (.data) from FLASH (ROM) to SRAM */
    ldr     r1, =__data_load__      /* Flash source */
    ldr     r2, =__data_start__     /* RAM destination start */
    ldr     r3, =__data_end__       /* RAM destination end */

copy_data_loop:
    cmp     r2, r3
    bhs     copy_data_done
    ldr     r0, [r1]
    str     r0, [r2]
    adds    r1, r1, #4
    adds    r2, r2, #4
    b       copy_data_loop

copy_data_done:

    /* Step 3: Zero-initialize uninitialized data (.bss) in SRAM */
    ldr     r1, =__bss_start__
    ldr     r2, =__bss_end__
    movs    r0, #0

zero_bss_loop:
    cmp     r1, r2
    bhs     zero_bss_done
    str     r0, [r1]
    adds    r1, r1, #4
    b       zero_bss_loop

zero_bss_done:

    /* Step 4: Jump to main program */
    bl      main

    /* Step 5: Fallback safety loop if main returns */
hang_loop:
    wfi
    b       hang_loop

/* ============================================================================
 * Default Exception Handlers
 * ============================================================================ */
    .thumb_func
NMI_Handler:
    b       .

    .thumb_func
HardFault_Handler:
    b       .

    .thumb_func
SVC_Handler:
    bx      lr

    .thumb_func
PendSV_Handler:
    bx      lr

    .thumb_func
SysTick_Handler:
    bx      lr

    .thumb_func
Default_Handler:
    bx      lr

    .end

