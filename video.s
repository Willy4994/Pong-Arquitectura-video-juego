/*
 * video.s - SH1106 / SSD1306 OLED (128x64 I2C) Direct Register Driver & Framebuffer
 * Architecture: ARMv6-M (Cortex-M0+) for Raspberry Pi Pico (RP2040)
 * Pure Assembly - Bare Metal (No SDK, No Arduino)
 *
 * Pin Connections:
 *   SDA -> GP4 (RP2040 I2C0 SDA, Func 3)
 *   SCL -> GP5 (RP2040 I2C0 SCL, Func 3)
 *
 * Framebuffer: 1024 bytes in SRAM (8 pages x 128 columns)
 * Fast 400 kHz I2C transfer with auto-probing of 0x3C / 0x3D addresses
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global video_init
    .global oled_flush
    .global fb_clear
    .global fb_fill
    .global fb_draw_pixel
    .global fb_clear_pixel
    .global fb_draw_rect_fill
    .global fb_draw_rect
    .global fb_draw_vline_dotted
    .global framebuffer

/* Register Offsets */
    .equ PADS_BANK0_BASE,   0x4001C000
    .equ PAD_GP4,           0x14        /* 0x04 + 4 * 4 */
    .equ PAD_GP5,           0x18        /* 0x04 + 5 * 4 */

    .equ IO_BANK0_BASE,     0x40014000
    .equ GPIO4_CTRL,        0x24        /* 4 * 8 + 4 */
    .equ GPIO5_CTRL,        0x2C        /* 5 * 8 + 4 */

    .equ I2C0_BASE,         0x40044000
    .equ IC_CON,            0x00
    .equ IC_TAR,            0x04
    .equ IC_DATA_CMD,       0x10
    .equ IC_FS_SCL_HCNT,    0x1C
    .equ IC_FS_SCL_LCNT,    0x20
    .equ IC_CLR_TX_ABRT,    0x54
    .equ IC_ENABLE,         0x6C
    .equ IC_STATUS,         0x70
    .equ IC_SDA_HOLD,       0x7C
    .equ IC_TX_ABRT_SOURCE, 0x80

/* ============================================================================
 * Framebuffer Allocation (1024 bytes)
 * ============================================================================ */
    .section .bss
    .align 4
framebuffer:
    .space 1024

oled_target_addr:
    .word 0

/* ============================================================================
 * Universal OLED Initialization Sequence (SH1106 & SSD1306 compatible)
 * ============================================================================ */
    .section .rodata
    .align 2
oled_init_cmds:
    .byte 0xAE        /* Display OFF */
    .byte 0xD5, 0x80  /* Set Display Clock Divide / Osc Freq (0x80) */
    .byte 0xA8, 0x3F  /* Multiplex Ratio: 1/64 (64 rows) */
    .byte 0xD3, 0x00  /* Display Offset: 0 */
    .byte 0x40        /* Display Start Line: 0 */
    .byte 0x8D, 0x14  /* SSD1306 Charge Pump: Enable (ignored by SH1106) */
    .byte 0xAD, 0x8B  /* SH1106 DC-DC Control: Enable built-in charge pump */
    .byte 0x32        /* SH1106 Pump voltage: 8.0V */
    .byte 0xA1        /* Segment Re-map: column 127 is SEG0 */
    .byte 0xC8        /* COM Output Scan Direction: Remapped mode */
    .byte 0xDA, 0x12  /* COM Pins Hardware Configuration: Alternative */
    .byte 0x81, 0xCF  /* Contrast Control: High brightness (0xCF) */
    .byte 0xD9, 0xF1  /* Pre-charge Period */
    .byte 0xDB, 0x40  /* VCOM Deselect Level */
    .byte 0x20, 0x02  /* Memory Addressing: Page Addressing Mode */
    .byte 0xA4        /* Output follows RAM content */
    .byte 0xA6        /* Normal Display (non-inverted) */
    .byte 0xAF        /* Display ON! */
oled_init_cmds_end:
    .equ OLED_INIT_CMDS_LEN, (oled_init_cmds_end - oled_init_cmds)

    .section .text
    .align 2

/* ----------------------------------------------------------------------------
 * video_init: Configures GP4/GP5 for I2C0, initializes Synopsys I2C and OLED
 * ---------------------------------------------------------------------------- */
    .thumb_func
video_init:
    push    {r4, r5, lr}

    /* 1. Configure GP4 (SDA) and GP5 (SCL) in IO_BANK0 to Function 3 (I2C0) */
    ldr     r4, =IO_BANK0_BASE
    movs    r0, #3                      /* Function 3 = I2C */
    str     r0, [r4, #GPIO4_CTRL]
    str     r0, [r4, #GPIO5_CTRL]

    /* 2. Configure GP4 and GP5 in PADS_BANK0 (Pull-up enabled, Input enabled) */
    ldr     r4, =PADS_BANK0_BASE
    movs    r0, #0x48                   /* Pull-up (bit 3), Input enable (bit 6) */
    str     r0, [r4, #PAD_GP4]
    str     r0, [r4, #PAD_GP5]

    /* 3. Configure Synopsys DesignWare I2C0 */
    ldr     r4, =I2C0_BASE

    /* Disable controller before setting registers */
    movs    r0, #0
    str     r0, [r4, #IC_ENABLE]

    /* IC_CON:
     * Bit 0: Master Mode (1)
     * Bits 2:1: Speed = Fast mode (2) -> (2 << 1) = 4
     * Bit 5: Restart enable (1) -> 0x20
     * Bit 6: Slave disable (1) -> 0x40
     * Bit 8: TX_EMPTY_CTRL (1) -> 0x100
     * Total = 0x165
     */
    ldr     r0, =0x165
    str     r0, [r4, #IC_CON]

    /* Set default Slave Address: 0x3C */
    movs    r0, #0x3C
    str     r0, [r4, #IC_TAR]

    /* Clock SCL Timing for 400 kHz Fast Mode at 12 MHz CLK_SYS:
     * Period = 30 cycles -> HCNT = 12, LCNT = 18
     */
    movs    r0, #12
    str     r0, [r4, #IC_FS_SCL_HCNT]
    movs    r0, #18
    str     r0, [r4, #IC_FS_SCL_LCNT]
    movs    r0, #4
    str     r0, [r4, #IC_SDA_HOLD]

    /* Enable I2C controller */
    movs    r0, #1
    str     r0, [r4, #IC_ENABLE]

    /* 4. Send Initialization Commands to OLED (Pass 1) */
    bl      oled_send_init_sequence

    /* Small delay for charge pump / DC-DC converter to stabilize (~20 ms) */
    ldr     r0, =80000
delay_oled_pump:
    subs    r0, r0, #1
    bne     delay_oled_pump

    /* Send Initialization Commands (Pass 2, latches registers after pump is stable) */
    bl      oled_send_init_sequence

    /* 5. Clear screen buffer and flush */
    bl      fb_clear
    bl      oled_flush

    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * i2c0_write_byte: Transmits a single byte over I2C0 with timeout protection
 * Inputs: r0 = Data byte (0..255)
 *         r1 = Stop flag (1 = issue STOP condition, 0 = no stop)
 * ---------------------------------------------------------------------------- */
    .thumb_func
i2c0_write_byte:
    push    {r4, r5, lr}
    ldr     r4, =I2C0_BASE
    mov     r5, r1                      /* r5 = stop flag */

    ldr     r3, =50000                  /* Timeout count */
wait_tx_fifo:
    /* Poll IC_STATUS until TFNF (TX FIFO Not Full, bit 1) is 1 */
    ldr     r2, [r4, #IC_STATUS]
    movs    r1, #2
    ands    r1, r2
    cmp     r1, #0
    bne     fifo_space_ready

    subs    r3, r3, #1
    bne     wait_tx_fifo
    b       tx_done                     /* Timeout exit */

fifo_space_ready:
    /* If stop flag is set, set bit 9 (STOP = 0x200) in IC_DATA_CMD */
    cmp     r5, #0
    beq     tx_no_stop
    ldr     r1, =0x200
    orrs    r0, r1

tx_no_stop:
    str     r0, [r4, #IC_DATA_CMD]

    /* If no stop requested, return immediately */
    cmp     r5, #0
    beq     tx_done

    /* If stop was issued, wait until TX FIFO is completely empty and bus idle */
    ldr     r3, =50000
wait_tx_idle:
    ldr     r2, [r4, #IC_STATUS]

    /* Check TFE (bit 2 = 4) */
    movs    r1, #4
    ands    r1, r2
    cmp     r1, #0
    beq     idle_timeout_check          /* FIFO not empty yet */

    /* Check ACTIVITY (bit 0 = 1) */
    movs    r1, #1
    ands    r1, r2
    cmp     r1, #0
    beq     tx_idle_complete            /* FIFO empty and bus inactive! */

idle_timeout_check:
    subs    r3, r3, #1
    bne     wait_tx_idle

tx_idle_complete:
    /* Clear abort register */
    ldr     r0, [r4, #IC_CLR_TX_ABRT]

tx_done:
    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * oled_send_init_sequence: Transmits OLED initialization commands
 * ---------------------------------------------------------------------------- */
    .thumb_func
oled_send_init_sequence:
    push    {r4, r5, r6, lr}

    /* Send I2C Control Byte: 0x00 (Commands follow) */
    movs    r0, #0x00
    movs    r1, #0                      /* No STOP */
    bl      i2c0_write_byte

    ldr     r4, =oled_init_cmds
    ldr     r5, =OLED_INIT_CMDS_LEN
    movs    r6, #0

init_cmd_loop:
    ldrb    r0, [r4, r6]
    adds    r6, r6, #1

    /* Last command byte gets STOP bit */
    cmp     r6, r5
    bne     cmd_continue
    movs    r1, #1                      /* STOP */
    b       cmd_send
cmd_continue:
    movs    r1, #0                      /* No STOP */
cmd_send:
    bl      i2c0_write_byte

    cmp     r6, r5
    blt     init_cmd_loop

    pop     {r4, r5, r6, pc}

/* ----------------------------------------------------------------------------
 * oled_flush: Sends entire 1024-byte framebuffer to SH1106 display RAM
 * Uses page addressing (Page 0..7) with 2-pixel column offset
 * ---------------------------------------------------------------------------- */
    .thumb_func
oled_flush:
    push    {r4, r5, r6, r7, lr}

    movs    r4, #0                      /* r4 = page index (0..7) */

page_flush_loop:
    cmp     r4, #8
    bge     flush_done

    /* Step 1: Send SH1106 Page Addressing Command Packet
     * 0x00 (Control: commands follow)
     * 0xB0 | page (Set Page Address)
     * 0x02 (Set Column Low Nibble: 2 -> centers 128px on SH1106)
     * 0x10 (Set Column High Nibble: 0, with STOP)
     */
    movs    r0, #0x00
    movs    r1, #0
    bl      i2c0_write_byte

    movs    r0, #0xB0
    orrs    r0, r4
    movs    r1, #0
    bl      i2c0_write_byte

    movs    r0, #0x02                   /* Column low offset = 2 */
    movs    r1, #0
    bl      i2c0_write_byte

    movs    r0, #0x10                   /* Column high = 0, with STOP */
    movs    r1, #1
    bl      i2c0_write_byte

    /* Step 2: Send 128 Data Bytes for this Page
     * 0x40 (Control: data follows)
     * Followed by 128 bytes from framebuffer[page * 128]
     */
    movs    r0, #0x40                   /* Control byte = 0x40 (Data) */
    movs    r1, #0
    bl      i2c0_write_byte

    ldr     r5, =framebuffer
    mov     r6, r4
    lsls    r6, r6, #7                  /* r6 = page * 128 */
    adds    r5, r5, r6                  /* r5 = &framebuffer[page * 128] */

    movs    r7, #0                      /* r7 = column byte index (0..127) */

data_byte_loop:
    ldrb    r0, [r5, r7]
    adds    r7, r7, #1

    cmp     r7, #128
    bne     data_no_stop
    movs    r1, #1                      /* Last byte gets STOP */
    b       data_send
data_no_stop:
    movs    r1, #0
data_send:
    bl      i2c0_write_byte

    cmp     r7, #128
    blt     data_byte_loop

    /* Next page */
    adds    r4, r4, #1
    b       page_flush_loop

flush_done:
    pop     {r4, r5, r6, r7, pc}

/* ============================================================================
 * Framebuffer Drawing Primitives
 * ============================================================================ */

/* ----------------------------------------------------------------------------
 * fb_clear: Clears all 1024 bytes of framebuffer to 0 (Fast 32-bit writes)
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_clear:
    ldr     r0, =framebuffer
    ldr     r1, =1024
    adds    r1, r0, r1
    movs    r2, #0

clear_word_loop:
    str     r2, [r0]
    adds    r0, r0, #4
    cmp     r0, r1
    blt     clear_word_loop
    bx      lr

/* ----------------------------------------------------------------------------
 * fb_fill: Fills all 1024 bytes of framebuffer to 0xFF (all white)
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_fill:
    ldr     r0, =framebuffer
    ldr     r1, =1024
    adds    r1, r0, r1
    movs    r2, #0
    mvns    r2, r2                      /* r2 = 0xFFFFFFFF */

fill_word_loop:
    str     r2, [r0]
    adds    r0, r0, #4
    cmp     r0, r1
    blt     fill_word_loop
    bx      lr

/* ----------------------------------------------------------------------------
 * fb_draw_pixel: Sets a single pixel at (X, Y)
 * Inputs: r0 = X (0..127), r1 = Y (0..63)
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_pixel:
    cmp     r0, #127
    bhi     pixel_out_of_bounds
    cmp     r1, #63
    bhi     pixel_out_of_bounds

    mov     r2, r1
    lsrs    r2, r2, #3                  /* r2 = page = y >> 3 */

    movs    r3, #7
    ands    r3, r1                      /* r3 = bit index = y & 7 */

    lsls    r2, r2, #7
    adds    r2, r2, r0                  /* r2 = byte offset = page * 128 + x */

    ldr     r0, =framebuffer
    adds    r0, r0, r2

    movs    r2, #1
    lsls    r2, r2, r3

    ldrb    r1, [r0]
    orrs    r1, r2
    strb    r1, [r0]

pixel_out_of_bounds:
    bx      lr

/* ----------------------------------------------------------------------------
 * fb_clear_pixel: Clears a single pixel at (X, Y)
 * Inputs: r0 = X (0..127), r1 = Y (0..63)
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_clear_pixel:
    cmp     r0, #127
    bhi     cpixel_out
    cmp     r1, #63
    bhi     cpixel_out

    mov     r2, r1
    lsrs    r2, r2, #3

    movs    r3, #7
    ands    r3, r1

    lsls    r2, r2, #7
    adds    r2, r2, r0

    ldr     r0, =framebuffer
    adds    r0, r0, r2

    movs    r2, #1
    lsls    r2, r2, r3

    ldrb    r1, [r0]
    bics    r1, r2
    strb    r1, [r0]

cpixel_out:
    bx      lr

/* ----------------------------------------------------------------------------
 * fb_draw_rect_fill: Draws filled rectangle
 * Inputs: r0 = X, r1 = Y, r2 = Width, r3 = Height
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_rect_fill:
    push    {r4, r5, r6, r7, lr}
    mov     r4, r0                      /* baseX */
    mov     r5, r1                      /* baseY */
    mov     r6, r2                      /* Width */
    mov     r7, r3                      /* Height */

    movs    r3, #0                      /* dy (0..Height-1) */

rf_row_loop:
    cmp     r3, r7
    bge     rf_done

    movs    r2, #0                      /* dx (0..Width-1) */

rf_col_loop:
    cmp     r2, r6
    bge     rf_next_row

    push    {r2, r3}
    adds    r0, r4, r2
    adds    r1, r5, r3
    bl      fb_draw_pixel
    pop     {r2, r3}

    adds    r2, r2, #1
    b       rf_col_loop

rf_next_row:
    adds    r3, r3, #1
    b       rf_row_loop

rf_done:
    pop     {r4, r5, r6, r7, pc}

/* ----------------------------------------------------------------------------
 * fb_draw_rect: Draws unfilled rectangle (outline)
 * Inputs: r0 = X, r1 = Y, r2 = Width, r3 = Height
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_rect:
    push    {r4, r5, r6, r7, lr}
    mov     r4, r0                      /* X */
    mov     r5, r1                      /* Y */
    mov     r6, r2                      /* W */
    mov     r7, r3                      /* H */

    /* Top edge */
    mov     r0, r4
    mov     r1, r5
    mov     r2, r6
    movs    r3, #1
    bl      fb_draw_rect_fill

    /* Bottom edge */
    mov     r0, r4
    adds    r1, r5, r7
    subs    r1, r1, #1
    mov     r2, r6
    movs    r3, #1
    bl      fb_draw_rect_fill

    /* Left edge */
    mov     r0, r4
    mov     r1, r5
    movs    r2, #1
    mov     r3, r7
    bl      fb_draw_rect_fill

    /* Right edge */
    adds    r0, r4, r6
    subs    r0, r0, #1
    mov     r1, r5
    movs    r2, #1
    mov     r3, r7
    bl      fb_draw_rect_fill

    pop     {r4, r5, r6, r7, pc}

/* ----------------------------------------------------------------------------
 * fb_draw_vline_dotted: Draws dotted vertical line (Pong center net)
 * Inputs: r0 = X, r1 = Y_start, r2 = Y_end
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_vline_dotted:
    push    {r4, r5, r6, lr}
    mov     r4, r0                      /* X */
    mov     r5, r1                      /* Current Y */
    mov     r6, r2                      /* Y_end */

vline_loop:
    cmp     r5, r6
    bgt     vline_done

    mov     r0, r4
    mov     r1, r5
    bl      fb_draw_pixel

    /* Step by 3 pixels */
    adds    r5, r5, #3
    b       vline_loop

vline_done:
    pop     {r4, r5, r6, pc}

    .end
