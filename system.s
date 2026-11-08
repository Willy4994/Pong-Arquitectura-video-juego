/*
 * system.s - System Initialization: XOSC (12MHz), Clocks, Watchdog Tick & Resets
 * Architecture: ARMv6-M (Cortex-M0+) for Raspberry Pi Pico (RP2040)
 * Pure Assembly - Bare Metal
 *
 * Configures:
 *   1. XOSC (12 MHz external crystal on Pico)
 *   2. CLK_REF and CLK_SYS switched to 12 MHz XOSC
 *   3. CLK_PERI enabled for I2C and peripheral blocks
 *   4. CLK_ADC enabled for ADC conversion blocks
 *   5. WATCHDOG_TICK configured for 1 MHz microsecond timebase (required by Hardware Timer)
 *   6. Subsystem Resets released: IO_BANK0, PADS_BANK0, I2C0, ADC, TIMER
 *   7. Onboard Green LED (GP25) turned ON as hardware heartbeat indicator
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global system_init
    .global led_on
    .global led_off
    .global led_toggle

/* Base Addresses */
    .equ XOSC_BASE,         0x40024000
    .equ XOSC_CTRL,         0x00
    .equ XOSC_STATUS,       0x04
    .equ XOSC_STARTUP,      0x0C

    .equ CLOCKS_BASE,       0x40008000
    .equ CLK_REF_CTRL,      0x30
    .equ CLK_REF_SELECTED,  0x38
    .equ CLK_SYS_CTRL,      0x3C
    .equ CLK_SYS_SELECTED,  0x44
    .equ CLK_PERI_CTRL,     0x48
    .equ CLK_ADC_CTRL,      0x60
    .equ CLK_ADC_DIV,       0x64

    .equ WATCHDOG_BASE,     0x40058000
    .equ WATCHDOG_TICK,     0x2C

    .equ RESETS_BASE,       0x4000C000
    .equ RESETS_CLR_ALIAS,  0x4000F000
    .equ RESETS_RESET_DONE, 0x08
    /* Mask: ADC (bit 0), I2C0 (bit 3), IO_BANK0 (bit 5), PADS_BANK0 (bit 8), TIMER (bit 21) */
    .equ RESETS_ALL_MASK,   0x00200129

    .equ PADS_BANK0_BASE,   0x4001C000
    .equ PAD_GP25,          0x68        /* 0x04 + 25 * 4 */

    .equ IO_BANK0_BASE,     0x40014000
    .equ GPIO25_CTRL,       0xCC        /* 25 * 8 + 4 */

    .equ SIO_BASE,          0xD0000000
    .equ SIO_GPIO_OUT_SET,  0x14
    .equ SIO_GPIO_OUT_CLR,  0x18
    .equ SIO_GPIO_OUT_XOR,  0x1C
    .equ SIO_GPIO_OE_SET,   0x24
    .equ LED_PIN_MASK,      0x02000000  /* Bit 25 = GP25 */

    .section .text
    .align 2

/* ----------------------------------------------------------------------------
 * system_init: Master Hardware Initialization Routine
 * ---------------------------------------------------------------------------- */
    .thumb_func
system_init:
    push    {r4, r5, lr}

    /* ========================================================================
     * Step 1: Start 12 MHz Crystal Oscillator (XOSC)
     * ======================================================================== */
    ldr     r4, =XOSC_BASE

    /* Startup delay: 47 (~1 ms for 12 MHz crystal) */
    movs    r0, #47
    str     r0, [r4, #XOSC_STARTUP]

    /* Enable XOSC with 1-15 MHz range: (0xFAB << 12) | 0xAA0 = 0x00FABAA0 */
    ldr     r0, =0x00FABAA0
    str     r0, [r4, #XOSC_CTRL]

wait_xosc_stable:
    ldr     r0, [r4, #XOSC_STATUS]
    /* Bit 31 is STABLE. If bit 31 is 0, r0 is positive (bpl loops) */
    cmp     r0, #0
    bpl     wait_xosc_stable

    /* ========================================================================
     * Step 2: Configure Clocks to 12 MHz XOSC
     * ======================================================================== */
    ldr     r4, =CLOCKS_BASE

    /* 2a. Switch CLK_REF to XOSC (SRC = 2) */
    movs    r0, #2
    str     r0, [r4, #CLK_REF_CTRL]

wait_ref_switch:
    ldr     r0, [r4, #CLK_REF_SELECTED]
    movs    r1, #4                      /* Bit 2 = 1 << 2 */
    ands    r0, r1
    cmp     r0, #0
    beq     wait_ref_switch

    /* 2b. Connect CLK_SYS to CLK_REF (SRC = 0) */
    movs    r0, #0
    str     r0, [r4, #CLK_SYS_CTRL]

wait_sys_switch:
    ldr     r0, [r4, #CLK_SYS_SELECTED]
    movs    r1, #1                      /* Bit 0 = 1 << 0 */
    ands    r0, r1
    cmp     r0, #0
    beq     wait_sys_switch

    /* 2c. Enable CLK_PERI (Source = CLK_SYS, ENABLE = Bit 11 -> 0x800) */
    ldr     r0, =0x00000800
    str     r0, [r4, #CLK_PERI_CTRL]

    /* 2d. Enable CLK_ADC (Source = XOSC 12 MHz, AUXSRC = 3 -> (3 << 5) = 0x60, ENABLE = 0x800 -> 0x860) */
    ldr     r0, =0x00000860
    str     r0, [r4, #CLK_ADC_CTRL]

    /* Set ADC Clock Divider = 1 (Integer divisor = 1 in bits 9:8 -> 0x0100) */
    ldr     r0, =0x00000100
    str     r0, [r4, #CLK_ADC_DIV]

    /* ========================================================================
     * Step 3: Configure Watchdog 1 MHz Microsecond Tick
     * Required by the 64-bit Hardware Timer to increment 1us per tick
     * Cycles = 12 (for 12 MHz clk_ref), Enable = Bit 9 -> (1 << 9) | 12 = 0x020C
     * ======================================================================== */
    ldr     r4, =WATCHDOG_BASE
    ldr     r0, =0x0000020C
    str     r0, [r4, #WATCHDOG_TICK]

    /* ========================================================================
     * Step 4: Release Subsystem Resets
     * IO_BANK0, PADS_BANK0, I2C0, ADC, TIMER
     * ======================================================================== */
    ldr     r4, =RESETS_CLR_ALIAS
    ldr     r0, =RESETS_ALL_MASK
    str     r0, [r4]

    ldr     r4, =RESETS_BASE
wait_resets:
    ldr     r1, [r4, #RESETS_RESET_DONE]
    ands    r1, r0
    cmp     r1, r0
    bne     wait_resets

    /* ========================================================================
     * Step 5: Configure and Turn ON Onboard Green LED (GP25)
     * Provides immediate visual confirmation that bare-metal code is executing
     * ======================================================================== */
    /* Pad GP25: Drive strength 4mA, Output enable -> 0x00 */
    ldr     r4, =PADS_BANK0_BASE
    movs    r0, #0
    str     r0, [r4, #PAD_GP25]

    /* IO_BANK0 GP25: Function 5 (SIO) */
    ldr     r4, =IO_BANK0_BASE
    movs    r0, #5
    movs    r1, #GPIO25_CTRL
    str     r0, [r4, r1]

    /* SIO: Enable Output for GP25 and drive HIGH */
    ldr     r4, =SIO_BASE
    ldr     r0, =LED_PIN_MASK
    str     r0, [r4, #SIO_GPIO_OE_SET]  /* Output Enable */
    str     r0, [r4, #SIO_GPIO_OUT_SET] /* Drive HIGH -> LED ON! */

    /* ========================================================================
     * Step 6: Power-On Stabilization Delay (~100 ms at 12 MHz)
     * Allows the OLED module power rail, charge pump caps, and POR to settle
     * ======================================================================== */
    ldr     r0, =400000
delay_por:
    subs    r0, r0, #1
    bne     delay_por

    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * LED Control Utility Functions
 * ---------------------------------------------------------------------------- */
    .thumb_func
led_on:
    ldr     r1, =SIO_BASE
    ldr     r0, =LED_PIN_MASK
    str     r0, [r1, #SIO_GPIO_OUT_SET]
    bx      lr

    .thumb_func
led_off:
    ldr     r1, =SIO_BASE
    ldr     r0, =LED_PIN_MASK
    str     r1, [r1, #SIO_GPIO_OUT_CLR]
    bx      lr

    .thumb_func
led_toggle:
    ldr     r1, =SIO_BASE
    ldr     r0, =LED_PIN_MASK
    str     r0, [r1, #SIO_GPIO_OUT_XOR]
    bx      lr

    .end

