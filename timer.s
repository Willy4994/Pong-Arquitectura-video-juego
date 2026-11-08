/*
 * timer.s - Hardware Timer & NVIC Interrupt Driver for RP2040
 * Architecture: ARMv6-M (Cortex-M0+)
 * Pure Assembly - Bare Metal (Direct Register Access)
 *
 * Configures RP2040 64-bit Hardware Timer (ALARM0) at 60 FPS (16.6ms / tick).
 * Complies with strict non-blocking hardware interrupt requirements.
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global timer_init
    .global timer_start
    .global timer_stop
    .global timer_wait_tick
    .global TIMER_IRQ_0_Handler
    .global game_tick_flag
    .global tick_counter

/* Register Base Addresses and Offsets */
    .equ TIMER_BASE,        0x40054000
    .equ TIMER_TIMELR,      0x0C        /* Read low 32 bits of microsecond timer */
    .equ TIMER_ALARM0,      0x10        /* Alarm 0 match register */
    .equ TIMER_ARMED,       0x20        /* Armed status (write 1 to disarm) */
    .equ TIMER_INTR,        0x34        /* Interrupt status / clear */
    .equ TIMER_INTE,        0x38        /* Interrupt enable */

    .equ NVIC_ISER,         0xE000E100  /* NVIC Interrupt Set-Enable Register */
    .equ NVIC_ICER,         0xE000E180  /* NVIC Interrupt Clear-Enable Register */

    /* 60 FPS = 16666 microseconds (1/60s = 0.016666s) */
    .equ TICK_INTERVAL_US,  16666

/* ============================================================================
 * RAM Data for Timer
 * ============================================================================ */
    .section .bss
    .align 2
game_tick_flag:
    .word 0                 /* Set to 1 by ISR on every timer tick */
tick_counter:
    .word 0                 /* Monotonically increasing tick counter */
timer_is_running:
    .word 0                 /* 1 if running, 0 if paused/stopped */

/* ============================================================================
 * Code Section
 * ============================================================================ */
    .section .text
    .align 2

/* ----------------------------------------------------------------------------
 * timer_init: Initializes ALARM0 and NVIC IRQ 0
 * ---------------------------------------------------------------------------- */
    .thumb_func
timer_init:
    push    {r4, lr}

    /* Reset tick variables */
    ldr     r0, =game_tick_flag
    movs    r1, #0
    str     r1, [r0]
    ldr     r0, =tick_counter
    str     r1, [r0]

    /* Start timer */
    bl      timer_start

    pop     {r4, pc}

/* ----------------------------------------------------------------------------
 * timer_start: Arms ALARM0 for (TIMELR + 16666us) and enables NVIC IRQ 0
 * ---------------------------------------------------------------------------- */
    .thumb_func
timer_start:
    push    {r4, r5, lr}

    ldr     r4, =TIMER_BASE

    /* Clear any pending interrupt on ALARM0 (write 1 to bit 0 of TIMER_INTR) */
    movs    r1, #1
    str     r1, [r4, #TIMER_INTR]

    /* Read current timestamp */
    ldr     r2, [r4, #TIMER_TIMELR]
    ldr     r3, =TICK_INTERVAL_US
    adds    r2, r2, r3

    /* Set next alarm match value */
    str     r2, [r4, #TIMER_ALARM0]

    /* Enable ALARM0 interrupt in TIMER_INTE */
    ldr     r1, [r4, #TIMER_INTE]
    movs    r2, #1
    orrs    r1, r2
    str     r1, [r4, #TIMER_INTE]

    /* Enable IRQ 0 in NVIC (NVIC_ISER) */
    ldr     r4, =NVIC_ISER
    movs    r1, #1
    str     r1, [r4]

    /* Update running state */
    ldr     r0, =timer_is_running
    movs    r1, #1
    str     r1, [r0]

    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * timer_stop: Disables ALARM0 and NVIC IRQ 0 (Used on Game Over)
 * ---------------------------------------------------------------------------- */
    .thumb_func
timer_stop:
    push    {r4, lr}

    /* Disable IRQ 0 in NVIC (NVIC_ICER) */
    ldr     r4, =NVIC_ICER
    movs    r1, #1
    str     r1, [r4]

    /* Disable ALARM0 in TIMER_INTE */
    ldr     r4, =TIMER_BASE
    ldr     r1, [r4, #TIMER_INTE]
    movs    r2, #1
    bics    r1, r2
    str     r1, [r4, #TIMER_INTE]

    /* Disarm ALARM0 (write 1 to bit 0 of TIMER_ARMED) */
    movs    r1, #1
    str     r1, [r4, #TIMER_ARMED]

    /* Update running state */
    ldr     r0, =timer_is_running
    movs    r1, #0
    str     r1, [r0]

    pop     {r4, pc}

/* ----------------------------------------------------------------------------
 * timer_wait_tick: Waits using WFI until hardware timer interrupt sets flag
 * Ensures exact 60 FPS timing with zero busy-loop CPU burn
 * ---------------------------------------------------------------------------- */
    .thumb_func
timer_wait_tick:
    push    {r4, lr}
    ldr     r4, =game_tick_flag

wait_loop:
    ldr     r0, [r4]
    cmp     r0, #0
    bne     tick_ready

    /* Sleep CPU until next hardware interrupt wakes it up */
    wfi
    b       wait_loop

tick_ready:
    /* Consume tick flag */
    movs    r0, #0
    str     r0, [r4]

    pop     {r4, pc}

/* ----------------------------------------------------------------------------
 * TIMER_IRQ_0_Handler: Interrupt Service Routine for RP2040 Timer ALARM0
 * Automatically executed by Cortex-M0+ NVIC on alarm match
 * ---------------------------------------------------------------------------- */
    .thumb_func
TIMER_IRQ_0_Handler:
    /* Low registers r0-r3, r12, lr, pc, psr are automatically preserved by HW */
    ldr     r0, =TIMER_BASE

    /* Clear interrupt flag in TIMER_INTR (write 1 to bit 0) */
    movs    r1, #1
    str     r1, [r0, #TIMER_INTR]

    /* Schedule next tick (TIMELR + TICK_INTERVAL_US) */
    ldr     r2, [r0, #TIMER_TIMELR]
    ldr     r3, =TICK_INTERVAL_US
    adds    r2, r2, r3
    str     r2, [r0, #TIMER_ALARM0]

    /* Set game tick flag */
    ldr     r0, =game_tick_flag
    movs    r1, #1
    str     r1, [r0]

    /* Increment total tick counter */
    ldr     r0, =tick_counter
    ldr     r1, [r0]
    adds    r1, r1, #1
    str     r1, [r0]

    /* Return from exception */
    bx      lr

    .end

