/*
 * font.s - 5x7 Monochrome Font and Text Rendering Routines
 * Architecture: ARMv6-M (Cortex-M0+)
 * Pure Assembly - Bare Metal
 *
 * Provides ASCII characters: '0'-'9', 'A'-'Z', ':', '-', '!', ' '
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global fb_draw_char
    .global fb_draw_string
    .global fb_draw_number
    .global font5x7_data

    .extern fb_draw_pixel

    .section .rodata
    .align 2

/* 5x7 Font Bitmaps (5 bytes per character, columns 0 to 4, bit 0 = top pixel) */
font5x7_data:
    /* Digits '0'..'9' (Indices 0..9) */
    /* '0' (0) */ .byte 0x3E, 0x51, 0x49, 0x45, 0x3E
    /* '1' (1) */ .byte 0x00, 0x42, 0x7F, 0x40, 0x00
    /* '2' (2) */ .byte 0x42, 0x61, 0x51, 0x49, 0x46
    /* '3' (3) */ .byte 0x21, 0x41, 0x45, 0x4B, 0x31
    /* '4' (4) */ .byte 0x18, 0x14, 0x12, 0x7F, 0x10
    /* '5' (5) */ .byte 0x27, 0x45, 0x45, 0x45, 0x39
    /* '6' (6) */ .byte 0x3C, 0x4A, 0x49, 0x49, 0x30
    /* '7' (7) */ .byte 0x01, 0x71, 0x09, 0x05, 0x03
    /* '8' (8) */ .byte 0x36, 0x49, 0x49, 0x49, 0x36
    /* '9' (9) */ .byte 0x06, 0x49, 0x49, 0x29, 0x1E

    /* Uppercase Letters 'A'..'Z' (Indices 10..35) */
    /* 'A' (10) */ .byte 0x7E, 0x11, 0x11, 0x11, 0x7E
    /* 'B' (11) */ .byte 0x7F, 0x49, 0x49, 0x49, 0x36
    /* 'C' (12) */ .byte 0x3E, 0x41, 0x41, 0x41, 0x22
    /* 'D' (13) */ .byte 0x7F, 0x41, 0x41, 0x22, 0x1C
    /* 'E' (14) */ .byte 0x7F, 0x49, 0x49, 0x49, 0x41
    /* 'F' (15) */ .byte 0x7F, 0x09, 0x09, 0x09, 0x01
    /* 'G' (16) */ .byte 0x3E, 0x41, 0x49, 0x49, 0x7A
    /* 'H' (17) */ .byte 0x7F, 0x08, 0x08, 0x08, 0x7F
    /* 'I' (18) */ .byte 0x00, 0x41, 0x7F, 0x41, 0x00
    /* 'J' (19) */ .byte 0x20, 0x40, 0x41, 0x3F, 0x01
    /* 'K' (20) */ .byte 0x7F, 0x08, 0x14, 0x22, 0x41
    /* 'L' (21) */ .byte 0x7F, 0x40, 0x40, 0x40, 0x40
    /* 'M' (22) */ .byte 0x7F, 0x02, 0x0C, 0x02, 0x7F
    /* 'N' (23) */ .byte 0x7F, 0x04, 0x08, 0x10, 0x7F
    /* 'O' (24) */ .byte 0x3E, 0x41, 0x41, 0x41, 0x3E
    /* 'P' (25) */ .byte 0x7F, 0x09, 0x09, 0x09, 0x06
    /* 'Q' (26) */ .byte 0x3E, 0x41, 0x51, 0x21, 0x5E
    /* 'R' (27) */ .byte 0x7F, 0x09, 0x19, 0x29, 0x46
    /* 'S' (28) */ .byte 0x46, 0x49, 0x49, 0x49, 0x31
    /* 'T' (29) */ .byte 0x01, 0x01, 0x7F, 0x01, 0x01
    /* 'U' (30) */ .byte 0x3F, 0x40, 0x40, 0x40, 0x3F
    /* 'V' (31) */ .byte 0x1F, 0x20, 0x40, 0x20, 0x1F
    /* 'W' (32) */ .byte 0x7F, 0x20, 0x18, 0x20, 0x7F
    /* 'X' (33) */ .byte 0x63, 0x14, 0x08, 0x14, 0x63
    /* 'Y' (34) */ .byte 0x07, 0x08, 0x70, 0x08, 0x07
    /* 'Z' (35) */ .byte 0x61, 0x51, 0x49, 0x45, 0x43

    /* Special Symbols */
    /* ':' (36) */ .byte 0x00, 0x36, 0x36, 0x00, 0x00
    /* '-' (37) */ .byte 0x08, 0x08, 0x08, 0x08, 0x08
    /* '!' (38) */ .byte 0x00, 0x00, 0x5F, 0x00, 0x00
    /* ' ' (39) */ .byte 0x00, 0x00, 0x00, 0x00, 0x00

    .section .text
    .align 2

/* ----------------------------------------------------------------------------
 * get_font_index: Maps ASCII byte to font index (0..39)
 * Input:  r0 = ASCII character
 * Output: r0 = Index (0..39)
 * ---------------------------------------------------------------------------- */
    .thumb_func
get_font_index:
    /* Digits '0'..'9' (0x30..0x39) */
    cmp     r0, #'0'
    blt     chk_special
    cmp     r0, #'9'
    bgt     chk_upper
    subs    r0, r0, #'0'
    bx      lr

chk_upper:
    /* Uppercase 'A'..'Z' (0x41..0x5A) */
    cmp     r0, #'A'
    blt     chk_special
    cmp     r0, #'Z'
    bgt     chk_lower
    subs    r0, r0, #'A'
    adds    r0, r0, #10
    bx      lr

chk_lower:
    /* Lowercase 'a'..'z' (0x61..0x7A) -> Convert to uppercase */
    cmp     r0, #'a'
    blt     chk_special
    cmp     r0, #'z'
    bgt     chk_special
    subs    r0, r0, #'a'
    adds    r0, r0, #10
    bx      lr

chk_special:
    cmp     r0, #':'
    bne     chk_dash
    movs    r0, #36
    bx      lr

chk_dash:
    cmp     r0, #'-'
    bne     chk_excl
    movs    r0, #37
    bx      lr

chk_excl:
    cmp     r0, #'!'
    bne     chk_space
    movs    r0, #38
    bx      lr

chk_space:
    movs    r0, #39
    bx      lr

/* ----------------------------------------------------------------------------
 * fb_draw_char: Renders a single 5x7 character to the framebuffer
 * Inputs: r0 = X (0..127)
 *         r1 = Y (0..63)
 *         r2 = ASCII character
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_char:
    push    {r4, r5, r6, r7, lr}
    mov     r4, r0              /* r4 = baseX */
    mov     r5, r1              /* r5 = baseY */

    mov     r0, r2
    bl      get_font_index      /* r0 = font index */

    /* Offset = index * 5 */
    movs    r1, #5
    muls    r0, r1

    ldr     r1, =font5x7_data
    adds    r6, r1, r0          /* r6 = pointer to 5 glyph bytes */

    movs    r7, #0              /* r7 = col (0..4) */

char_col_loop:
    cmp     r7, #5
    bge     char_done

    ldrb    r3, [r6, r7]        /* r3 = column bitmap byte (bits 0..6) */
    movs    r2, #0              /* r2 = row (0..6) */

char_row_loop:
    cmp     r2, #7
    bge     char_next_col

    /* Check if bit 'r2' of r3 is set: (r3 >> r2) & 1 */
    mov     r1, r3
    lsrs    r1, r2
    movs    r0, #1
    ands    r1, r0
    cmp     r1, #0
    beq     char_skip_pixel

    /* Pixel is ON: draw at (baseX + col, baseY + row) */
    push    {r2, r3}
    adds    r0, r4, r7          /* r0 = X */
    adds    r1, r5, r2          /* r1 = Y */
    bl      fb_draw_pixel
    pop     {r2, r3}

char_skip_pixel:
    adds    r2, r2, #1
    b       char_row_loop

char_next_col:
    adds    r7, r7, #1
    b       char_col_loop

char_done:
    pop     {r4, r5, r6, r7, pc}

/* ----------------------------------------------------------------------------
 * fb_draw_string: Draws a null-terminated ASCII string
 * Inputs: r0 = X
 *         r1 = Y
 *         r2 = Pointer to null-terminated string
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_string:
    push    {r4, r5, r6, lr}
    mov     r4, r0              /* r4 = current X */
    mov     r5, r1              /* r5 = Y */
    mov     r6, r2              /* r6 = string pointer */

str_loop:
    ldrb    r2, [r6]
    cmp     r2, #0
    beq     str_done

    mov     r0, r4
    mov     r1, r5
    bl      fb_draw_char

    /* Advance X by 6 pixels (5 width + 1 space) */
    adds    r4, r4, #6
    adds    r6, r6, #1
    b       str_loop

str_done:
    pop     {r4, r5, r6, pc}

/* ----------------------------------------------------------------------------
 * fb_draw_number: Formats and draws an unsigned integer (0..99)
 * Inputs: r0 = X
 *         r1 = Y
 *         r2 = Number (0..99)
 * ---------------------------------------------------------------------------- */
    .thumb_func
fb_draw_number:
    push    {r4, r5, r6, lr}
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2

    /* Compute tens: r0 = r6 / 10, r1 = r6 % 10 */
    movs    r0, #0              /* tens */
    mov     r1, r6              /* units */
div10_loop:
    cmp     r1, #10
    blt     div10_done
    subs    r1, r1, #10
    adds    r0, r0, #1
    b       div10_loop

div10_done:
    /* If tens > 0, draw tens digit */
    cmp     r0, #0
    beq     draw_units_only

    /* Draw tens digit */
    push    {r1}
    movs    r2, #'0'
    adds    r2, r2, r0
    mov     r0, r4
    mov     r1, r5
    bl      fb_draw_char
    pop     {r1}

    /* Advance X for units */
    adds    r4, r4, #6

draw_units_only:
    /* Draw units digit */
    movs    r2, #'0'
    adds    r2, r2, r1
    mov     r0, r4
    mov     r1, r5
    bl      fb_draw_char

    pop     {r4, r5, r6, pc}

    .end
