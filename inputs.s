/*
 * inputs.s - Direct Register Driver for KY-023 Joystick and Button Z
 * Architecture: ARMv6-M (Cortex-M0+)
 * Pure Assembly - Bare Metal (No SDK, No Arduino)
 *
 * Pin Mapping:
 *   VRX -> GP26 (RP2040 ADC0)
 *   VRY -> GP27 (RP2040 ADC1)
 *   SW  -> GP14 (Button Z, Digital Input with internal pull-up)
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global inputs_init
    .global read_button_z
    .global read_adc_vrx
    .global read_adc_vry

/* Base Addresses */
    .equ PADS_BANK0_BASE,   0x4001C000
    .equ PAD_GP14,          0x3C        /* 0x04 + 14 * 4 */
    .equ PAD_GP26,          0x6C        /* 0x04 + 26 * 4 */
    .equ PAD_GP27,          0x70        /* 0x04 + 27 * 4 */

    .equ IO_BANK0_BASE,     0x40014000
    .equ GPIO14_CTRL,       0x74        /* 14 * 8 + 4 */
    .equ GPIO26_CTRL,       0xD4        /* 26 * 8 + 4 */
    .equ GPIO27_CTRL,       0xDC        /* 27 * 8 + 4 */

    .equ SIO_BASE,          0xD0000000
    .equ SIO_GPIO_IN,       0x04

    .equ ADC_BASE,          0x4004C000
    .equ ADC_CS,            0x00
    .equ ADC_RESULT,        0x04

    .section .text
    .align 2

/* ----------------------------------------------------------------------------
 * inputs_init: Configures GP14 (Button Z Pull-Up) and GP26/GP27 for ADC
 * ---------------------------------------------------------------------------- */
    .thumb_func
inputs_init:
    push    {r4, r5, lr}

    /* 1. Configure GP14 (Button Z):
     *    PADS_BANK0: Pull-up enabled (bit 3), Input enabled (bit 6) -> 0x48
     *    IO_BANK0:   Function 5 (SIO)
     */
    ldr     r4, =PADS_BANK0_BASE
    movs    r0, #0x48
    str     r0, [r4, #PAD_GP14]

    ldr     r4, =IO_BANK0_BASE
    movs    r0, #5                      /* Function 5 = SIO */
    str     r0, [r4, #GPIO14_CTRL]

    /* 2. Configure GP26 and GP27 for Analog Input (ADC0, ADC1):
     *    PADS_BANK0: Output Disable (bit 7), Input Disable (bit 6 = 0) -> 0x80
     *    IO_BANK0:   Function 0x1F (Null / disconnected from digital)
     */
    ldr     r4, =PADS_BANK0_BASE
    movs    r0, #0x80
    str     r0, [r4, #PAD_GP26]
    str     r0, [r4, #PAD_GP27]

    ldr     r4, =IO_BANK0_BASE
    movs    r0, #0x1F                   /* Function 0x1F = NULL */
    movs    r1, #GPIO26_CTRL
    str     r0, [r4, r1]
    movs    r1, #GPIO27_CTRL
    str     r0, [r4, r1]

    /* 3. Enable ADC peripheral (ADC_CS bit 0 = 1) */
    ldr     r4, =ADC_BASE
    movs    r0, #1                      /* EN = 1 */
    str     r0, [r4, #ADC_CS]

    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * read_button_z: Reads status of GP14 (Button Z / SW)
 * Returns: r0 = 1 if button is pressed (GND / active low), 0 if released
 * ---------------------------------------------------------------------------- */
    .thumb_func
read_button_z:
    ldr     r1, =SIO_BASE
    ldr     r0, [r1, #SIO_GPIO_IN]

    /* Check bit 14 (1 << 14 = 0x4000) */
    ldr     r2, =0x4000
    ands    r0, r2
    cmp     r0, #0
    beq     btn_pressed

    /* Button released (pulled HIGH) */
    movs    r0, #0
    bx      lr

btn_pressed:
    /* Button pressed (pulled to GND) */
    movs    r0, #1
    bx      lr

/* ----------------------------------------------------------------------------
 * read_adc_vrx: Reads GP26 / ADC Channel 0 (VRX axis)
 * Returns: r0 = 12-bit ADC value (0 to 4095)
 * ---------------------------------------------------------------------------- */
    .thumb_func
read_adc_vrx:
    push    {r4, lr}
    ldr     r4, =ADC_BASE

    /* Channel 0: AINSEL = 0, START_ONCE = 1 (bit 2), EN = 1 (bit 0) -> 0x0005 */
    movs    r0, #0x05
    str     r0, [r4, #ADC_CS]

    /* Fixed hardware conversion delay (takes 96 cycles of 12 MHz ADC clock = 8 us) */
    movs    r2, #100
vrx_delay:
    subs    r2, #1
    bne     vrx_delay

    /* Read converted 12-bit result */
    ldr     r0, [r4, #ADC_RESULT]
    ldr     r1, =0x0FFF
    ands    r0, r1
    pop     {r4, pc}

/* ----------------------------------------------------------------------------
 * read_adc_vry: Reads GP27 / ADC Channel 1 (VRY axis)
 * Returns: r0 = 12-bit ADC value (0 to 4095)
 * ---------------------------------------------------------------------------- */
    .thumb_func
read_adc_vry:
    push    {r4, lr}
    ldr     r4, =ADC_BASE

    /* Channel 1: AINSEL = 1 (bits 14:12 = 1 -> 0x1000), START_ONCE = 1, EN = 1 -> 0x1005 */
    ldr     r0, =0x1005
    str     r0, [r4, #ADC_CS]

    /* Fixed hardware conversion delay */
    movs    r2, #100
vry_delay:
    subs    r2, #1
    bne     vry_delay

    /* Read converted 12-bit result */
    ldr     r0, [r4, #ADC_RESULT]
    ldr     r1, =0x0FFF
    ands    r0, r1
    pop     {r4, pc}

    .end
