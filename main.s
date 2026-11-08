/*
 * main.s - Classic 2D Pong Video Game in Bare-Metal ARM Assembly
 * Architecture: ARMv6-M (Cortex-M0+) for Raspberry Pi Pico (RP2040)
 * Pure Assembly - 100% Bare-Metal (No SDK, No Arduino, No External Libraries)
 *
 * Direct Hardware Control:
 *   - OLED SH1106 128x64 via I2C0 (GP4=SDA, GP5=SCL)
 *   - KY-023 Joystick via ADC (GP26=VRX, GP27=VRY)
 *   - Button Z (SW) via SIO GPIO14 with pull-up
 *   - Hardware Timer via RP2040 ALARM0 and NVIC IRQ 0 (60 FPS)
 *
 * Game State Machine:
 *   0: STATE_MENU     (Static Start Screen, waits for Button Z)
 *   1: STATE_PLAYING  (60 FPS Physics, Collision Detection, AI, Scoreboard)
 *   2: STATE_GAMEOVER (Winner Screen, Total Timer Halt, Reset on Button Z)
 */

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .global main

    /* External drivers */
    .extern system_init
    .extern video_init
    .extern oled_flush
    .extern fb_clear
    .extern fb_fill
    .extern fb_draw_pixel
    .extern fb_draw_rect_fill
    .extern fb_draw_rect
    .extern fb_draw_vline_dotted
    .extern fb_draw_char
    .extern fb_draw_string
    .extern fb_draw_number

    .extern inputs_init
    .extern read_button_z
    .extern read_adc_vrx
    .extern read_adc_vry

    .extern timer_init
    .extern timer_start
    .extern timer_stop
    .extern timer_wait_tick

/* Game States */
    .equ STATE_MENU,        0
    .equ STATE_PLAYING,     1
    .equ STATE_GAMEOVER,    2

/* Game Constants */
    .equ PADDLE_W,          3
    .equ PADDLE_H,          14
    .equ P1_X,              4
    .equ CPU_X,             121
    .equ BALL_SIZE,         3
    .equ WINNING_SCORE,     5

/* ============================================================================
 * RAM Data for Pong State Machine & Physics
 * ============================================================================ */
    .section .bss
    .align 2

game_state:
    .word 0                 /* 0 = Menu, 1 = Playing, 2 = Game Over */

/* Paddle Coordinates (Y positions, 0..50) */
p1_y:
    .word 0
cpu_y:
    .word 0

/* Ball Coordinates and Velocities */
ball_x:
    .word 0
ball_y:
    .word 0
ball_vx:
    .word 0                 /* Horizontal speed (+1, -1, +2, -2) */
ball_vy:
    .word 0                 /* Vertical speed (+1, -1) */

/* Scoreboard */
score_p1:
    .word 0
score_cpu:
    .word 0
winner:
    .word 0                 /* 1 = Player 1 won, 2 = CPU won */

/* ============================================================================
 * Text Strings (RODATA)
 * ============================================================================ */
    .section .rodata
    .align 2

str_title_pong:     .asciz "PONG ARM"
str_sub_arch:       .asciz "ARQUITECTURA II"
str_press_z:        .asciz "PULSE BOTON Z"
str_game_over:      .asciz "GAME OVER"
str_p1_wins:        .asciz "HAS GANADO!"
str_cpu_wins:       .asciz "CPU GANA!"
str_score_hud:      .asciz "P1:    CPU:"
str_final_p1:       .asciz "P1:"
str_final_cpu:      .asciz "CPU:"
str_restart:        .asciz "PULSE Z REINICIAR"

/* ============================================================================
 * Main Entry Point
 * ============================================================================ */
    .section .text
    .align 2
    .thumb_func
main:
    push    {r4, lr}

    /* 1. Master System Initialization (XOSC, Clocks, Watchdog Tick, Resets, LED) */
    bl      system_init

    /* 2. Initialize Bare-Metal Hardware Peripherals */
    bl      inputs_init         /* Configure GPIO14 (Button Z) and ADC0/1 (Joystick) */
    bl      video_init          /* Configure I2C0 (GP4/5) and initialize SH1106 OLED */
    bl      timer_init          /* Configure 60 FPS Hardware Timer (NVIC IRQ 0) */

    /* 2. Initial State: Menu */
    ldr     r0, =game_state
    movs    r1, #STATE_MENU
    str     r1, [r0]

/* ============================================================================
 * Master Game Loop
 * ============================================================================ */
master_game_loop:
    ldr     r0, =game_state
    ldr     r0, [r0]

    cmp     r0, #STATE_MENU
    bne     not_menu
    b       run_state_menu
not_menu:
    cmp     r0, #STATE_PLAYING
    bne     not_playing
    b       run_state_playing
not_playing:
    cmp     r0, #STATE_GAMEOVER
    bne     master_game_loop
    b       run_state_gameover

/* ============================================================================
 * STATE 0: MENU PRINCIPAL
 * Static start screen with title, starts game when button Z is pressed
 * ============================================================================ */
run_state_menu:
    /* Render Menu Screen */
    bl      fb_clear

    /* Outer decorative border */
    movs    r0, #2
    movs    r1, #2
    movs    r2, #124
    movs    r3, #60
    bl      fb_draw_rect

    /* Title "PONG ARM" at (38, 12) */
    movs    r0, #38
    movs    r1, #12
    ldr     r2, =str_title_pong
    bl      fb_draw_string

    /* Subtitle "ARQUITECTURA II" at (20, 26) */
    movs    r0, #20
    movs    r1, #26
    ldr     r2, =str_sub_arch
    bl      fb_draw_string

    /* Prompt "PULSE BOTON Z" at (26, 44) */
    movs    r0, #26
    movs    r1, #44
    ldr     r2, =str_press_z
    bl      fb_draw_string

    /* Push buffer to OLED */
    bl      oled_flush

menu_wait_button:
    /* Check Button Z */
    bl      read_button_z
    cmp     r0, #1
    beq     menu_start_game

    /* Wait for timer tick to save power */
    bl      timer_wait_tick

    /* Re-flush menu periodically (every 16 ticks ~ 250 ms)
     * Guarantees display appears reliably on cold boot or wire reconnect */
    ldr     r0, =tick_counter
    ldr     r0, [r0]
    movs    r1, #15
    ands    r0, r1
    cmp     r0, #0
    bne     menu_wait_button

    bl      oled_flush
    b       menu_wait_button

menu_start_game:
    /* Debounce button: wait until released */
wait_release_menu:
    bl      read_button_z
    cmp     r0, #1
    bne     init_game_session
    bl      timer_wait_tick
    b       wait_release_menu

init_game_session:
    /* Reset Scores */
    ldr     r0, =score_p1
    movs    r1, #0
    str     r1, [r0]
    ldr     r0, =score_cpu
    str     r1, [r0]

    /* Reset Match State */
    bl      reset_match_round

    /* Switch to Playing state */
    ldr     r0, =game_state
    movs    r1, #STATE_PLAYING
    str     r1, [r0]

    /* Ensure Hardware Timer is running */
    bl      timer_start

    b       master_game_loop

/* ============================================================================
 * STATE 1: JUEGO EN CURSO (PLAYING)
 * Hardware Timer Synchronized (60 FPS), Physics, AI, Collisions, HUD
 * ============================================================================ */
run_state_playing:
    /* 1. Synchronize to exact 60 FPS hardware timer interrupt (No delay loops!) */
    bl      timer_wait_tick

    /* 2. Read Analog Joystick & Update Player Paddle */
    bl      update_player_paddle

    /* 3. Update Autonomous CPU Opponent Paddle (AI) */
    bl      update_cpu_ai

    /* 4. Update Ball Physics & Collisions */
    bl      update_ball_physics

    /* 5. Render Scene to Framebuffer */
    bl      render_game_scene

    /* 6. Push Framebuffer to OLED Display */
    bl      oled_flush

    b       master_game_loop

/* ----------------------------------------------------------------------------
 * update_player_paddle: Interprets ADC joystick variation and moves paddle
 * Automatically selects VRY or VRX based on user deflection
 * ---------------------------------------------------------------------------- */
    .thumb_func
update_player_paddle:
    push    {r4, r5, lr}

    /* Read VRY (GP27 / ADC1) */
    bl      read_adc_vry
    mov     r4, r0              /* r4 = vry (0..4095) */

    /* Read VRX (GP26 / ADC0) */
    bl      read_adc_vrx
    mov     r5, r0              /* r5 = vrx (0..4095) */

    /* Compute deflection from center (2048):
     * delta_y = abs(vry - 2048)
     * delta_x = abs(vrx - 2048)
     */
    ldr     r2, =2048

    subs    r0, r4, r2
    bge     pos_dy
    rsbs    r0, r0, #0
pos_dy:
    mov     r3, r0              /* r3 = delta_y */

    subs    r0, r5, r2
    bge     pos_dx
    rsbs    r0, r0, #0
pos_dx:                         /* r0 = delta_x */

    /* If delta_x > delta_y, use vrx; otherwise use vry */
    cmp     r0, r3
    ble     use_vry
    mov     r4, r5              /* use vrx value */

use_vry:
    /* Map ADC (0..4095) to Paddle Y: (val * 49) >> 12
     * Paddle height = 14, Playable range Y = 1 to 49
     */
    movs    r0, #49
    muls    r4, r0
    lsrs    r4, r4, #12         /* r4 = target Y (0..49) */

    /* Ensure minimum Y is 1 */
    cmp     r4, #1
    bge     p1_min_ok
    movs    r4, #1
p1_min_ok:
    /* Ensure maximum Y is 49 */
    cmp     r4, #49
    ble     p1_max_ok
    movs    r4, #49
p1_max_ok:

    /* Store player paddle Y */
    ldr     r0, =p1_y
    str     r4, [r0]

    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * update_cpu_ai: Autonomous AI for Opponent Paddle
 * Tracks ball Y smoothly with velocity capping
 * ---------------------------------------------------------------------------- */
    .thumb_func
update_cpu_ai:
    push    {r4, r5, lr}

    ldr     r0, =cpu_y
    ldr     r4, [r0]            /* r4 = cpu_y */

    ldr     r1, =ball_y
    ldr     r5, [r1]            /* r5 = ball_y */

    /* AI paddle center is cpu_y + 7 */
    adds    r1, r4, #7

    /* If ball moving towards CPU (vx > 0), track aggressively */
    ldr     r2, =ball_vx
    ldr     r2, [r2]
    cmp     r2, #0
    ble     ai_idle_center

    /* Ball is approaching: track ball center */
    cmp     r1, r5
    blt     ai_move_down
    bgt     ai_move_up
    b       ai_store

ai_move_down:
    /* Move paddle down by 1 pixel */
    adds    r4, r4, #1
    b       ai_store

ai_move_up:
    /* Move paddle up by 1 pixel */
    subs    r4, r4, #1
    b       ai_store

ai_idle_center:
    /* When ball is far, slowly drift toward court center (Y=24) */
    cmp     r4, #24
    blt     ai_drift_down
    bgt     ai_drift_up
    b       ai_store
ai_drift_down:
    adds    r4, r4, #1
    b       ai_store
ai_drift_up:
    subs    r4, r4, #1

ai_store:
    /* Clamp cpu_y between 1 and 49 */
    cmp     r4, #1
    bge     cpu_min_ok
    movs    r4, #1
cpu_min_ok:
    cmp     r4, #49
    ble     cpu_max_ok
    movs    r4, #49
cpu_max_ok:

    ldr     r0, =cpu_y
    str     r4, [r0]

    pop     {r4, r5, pc}

/* ----------------------------------------------------------------------------
 * update_ball_physics: Updates ball position and detects all collisions
 * ---------------------------------------------------------------------------- */
    .thumb_func
update_ball_physics:
    push    {r4, r5, r6, r7, lr}

    ldr     r0, =ball_x
    ldr     r4, [r0]            /* r4 = ball_x */

    ldr     r1, =ball_y
    ldr     r5, [r1]            /* r5 = ball_y */

    ldr     r2, =ball_vx
    ldr     r6, [r2]            /* r6 = ball_vx */

    ldr     r3, =ball_vy
    ldr     r7, [r3]            /* r7 = ball_vy */

    /* Update position */
    adds    r4, r4, r6
    adds    r5, r5, r7

    /* --- Collision 1: Top Wall (Y <= 1) --- */
    cmp     r5, #1
    bgt     chk_bottom_wall
    movs    r5, #1
    rsbs    r7, r7, #0          /* vy = -vy */
    b       chk_p1_paddle

chk_bottom_wall:
    /* --- Collision 2: Bottom Wall (Y + BALL_SIZE >= 63 -> Y >= 60) --- */
    cmp     r5, #60
    blt     chk_p1_paddle
    movs    r5, #60
    rsbs    r7, r7, #0          /* vy = -vy */

chk_p1_paddle:
    /* --- Collision 3: Player 1 Paddle (X = 4, Width = 3, Right edge = 7) --- */
    /* Ball must be at left edge (ball_x <= 7 and ball_x >= 4) */
    cmp     r4, #7
    bgt     chk_cpu_paddle
    cmp     r4, #3
    blt     chk_left_goal

    /* Check vertical overlap:
     * ball_y + BALL_SIZE >= p1_y  AND  ball_y <= p1_y + PADDLE_H
     */
    ldr     r0, =p1_y
    ldr     r0, [r0]            /* r0 = p1_y */

    adds    r1, r5, #BALL_SIZE
    cmp     r1, r0
    blt     chk_left_goal       /* Ball is above paddle */

    mov     r1, r0
    adds    r1, #PADDLE_H
    cmp     r5, r1
    bgt     chk_left_goal       /* Ball is below paddle */

    /* Hit Player Paddle! Bounce to right */
    movs    r4, #8
    movs    r6, #1              /* vx = +1 */

    /* Dynamic deflection: if hit top half, vy = -1; bottom half, vy = +1 */
    adds    r0, r0, #7          /* Paddle middle */
    cmp     r5, r0
    blt     p1_deflect_up
    movs    r7, #1
    b       chk_cpu_paddle
p1_deflect_up:
    movs    r7, #0
    subs    r7, r7, #1          /* r7 = -1 */
    b       chk_cpu_paddle

chk_cpu_paddle:
    /* --- Collision 4: CPU Paddle (X = 121, Width = 3) ---
     * Ball right edge = ball_x + BALL_SIZE (3) >= 121 -> ball_x >= 118
     */
    cmp     r4, #118
    blt     chk_goal
    cmp     r4, #122
    bgt     chk_right_goal

    /* Check vertical overlap */
    ldr     r0, =cpu_y
    ldr     r0, [r0]            /* r0 = cpu_y */

    adds    r1, r5, #BALL_SIZE
    cmp     r1, r0
    blt     chk_right_goal      /* Ball above paddle */

    mov     r1, r0
    adds    r1, #PADDLE_H
    cmp     r5, r1
    bgt     chk_right_goal      /* Ball below paddle */

    /* Hit CPU Paddle! Bounce to left */
    movs    r4, #117
    movs    r6, #0
    subs    r6, r6, #1          /* vx = -1 */

    adds    r0, r0, #7
    cmp     r5, r0
    blt     cpu_deflect_up
    movs    r7, #1
    b       chk_goal
cpu_deflect_up:
    movs    r7, #0
    subs    r7, r7, #1
    b       chk_goal

chk_goal:
chk_left_goal:
    /* Ball passed player on left: CPU scores point! */
    cmp     r4, #1
    bgt     chk_right_goal

    /* CPU Scores */
    ldr     r0, =score_cpu
    ldr     r1, [r0]
    adds    r1, r1, #1
    str     r1, [r0]

    /* Check Win Condition: CPU reaches 5 points */
    cmp     r1, #WINNING_SCORE
    blt     reset_round_after_goal

    /* CPU Wins match */
    ldr     r0, =winner
    movs    r1, #2              /* 2 = CPU */
    str     r1, [r0]

    ldr     r0, =game_state
    movs    r1, #STATE_GAMEOVER
    str     r1, [r0]

    /* Stop physical timer on Game Over */
    bl      timer_stop
    b       save_ball_vars

chk_right_goal:
    /* Ball passed CPU on right: Player scores point! */
    cmp     r4, #124
    blt     save_ball_vars

    /* Player Scores */
    ldr     r0, =score_p1
    ldr     r1, [r0]
    adds    r1, r1, #1
    str     r1, [r0]

    /* Check Win Condition: Player reaches 5 points */
    cmp     r1, #WINNING_SCORE
    blt     reset_round_after_goal

    /* Player Wins match */
    ldr     r0, =winner
    movs    r1, #1              /* 1 = Player */
    str     r1, [r0]

    ldr     r0, =game_state
    movs    r1, #STATE_GAMEOVER
    str     r1, [r0]

    /* Stop physical timer on Game Over */
    bl      timer_stop
    b       save_ball_vars

reset_round_after_goal:
    bl      reset_match_round
    b       ball_physics_done

save_ball_vars:
    ldr     r0, =ball_x
    str     r4, [r0]
    ldr     r1, =ball_y
    str     r5, [r1]
    ldr     r2, =ball_vx
    str     r6, [r2]
    ldr     r3, =ball_vy
    str     r7, [r3]

ball_physics_done:
    pop     {r4, r5, r6, r7, pc}

/* ----------------------------------------------------------------------------
 * reset_match_round: Centers ball and resets paddles for next serve
 * ---------------------------------------------------------------------------- */
    .thumb_func
reset_match_round:
    push    {lr}

    /* Center ball */
    ldr     r0, =ball_x
    movs    r1, #63
    str     r1, [r0]

    ldr     r0, =ball_y
    movs    r1, #30
    str     r1, [r0]

    /* Alternate ball serve direction based on tick */
    ldr     r0, =ball_vx
    movs    r1, #1
    str     r1, [r0]

    ldr     r0, =ball_vy
    movs    r1, #1
    str     r1, [r0]

    /* Center paddles */
    ldr     r0, =p1_y
    movs    r1, #25
    str     r1, [r0]

    ldr     r0, =cpu_y
    str     r1, [r0]

    pop     {pc}

/* ----------------------------------------------------------------------------
 * render_game_scene: Draws playfield, paddles, ball, and dynamic scoreboard HUD
 * ---------------------------------------------------------------------------- */
    .thumb_func
render_game_scene:
    push    {r4, r5, lr}

    bl      fb_clear

    /* 1. Top and Bottom Wall Borders */
    movs    r0, #0
    movs    r1, #0
    movs    r2, #128
    movs    r3, #1
    bl      fb_draw_rect_fill

    movs    r0, #0
    movs    r1, #63
    movs    r2, #128
    movs    r3, #1
    bl      fb_draw_rect_fill

    /* 2. Dotted Center Net */
    movs    r0, #63
    movs    r1, #1
    movs    r2, #62
    bl      fb_draw_vline_dotted

    /* 3. Scoreboard HUD (Font Mapping) */
    /* P1 Score at (48, 3) */
    movs    r0, #48
    movs    r1, #3
    ldr     r2, =score_p1
    ldr     r2, [r2]
    bl      fb_draw_number

    /* CPU Score at (72, 3) */
    movs    r0, #72
    movs    r1, #3
    ldr     r2, =score_cpu
    ldr     r2, [r2]
    bl      fb_draw_number

    /* 4. Draw Player Paddle at (P1_X, p1_y) */
    movs    r0, #P1_X
    ldr     r1, =p1_y
    ldr     r1, [r1]
    movs    r2, #PADDLE_W
    movs    r3, #PADDLE_H
    bl      fb_draw_rect_fill

    /* 5. Draw CPU Paddle at (CPU_X, cpu_y) */
    movs    r0, #CPU_X
    ldr     r1, =cpu_y
    ldr     r1, [r1]
    movs    r2, #PADDLE_W
    movs    r3, #PADDLE_H
    bl      fb_draw_rect_fill

    /* 6. Draw Ball at (ball_x, ball_y) */
    ldr     r0, =ball_x
    ldr     r0, [r0]
    ldr     r1, =ball_y
    ldr     r1, [r1]
    movs    r2, #BALL_SIZE
    movs    r3, #BALL_SIZE
    bl      fb_draw_rect_fill

    pop     {r4, r5, pc}

/* ============================================================================
 * STATE 2: GAME OVER
 * Screen showing match winner, physics halted, waiting for reset via Button Z
 * ============================================================================ */
run_state_gameover:
    /* Render Game Over Screen */
    bl      fb_clear

    /* Decorative border */
    movs    r0, #2
    movs    r1, #2
    movs    r2, #124
    movs    r3, #60
    bl      fb_draw_rect

    /* "GAME OVER" at (36, 8) */
    movs    r0, #36
    movs    r1, #8
    ldr     r2, =str_game_over
    bl      fb_draw_string

    /* Check who won: 1 = Player, 2 = CPU */
    ldr     r0, =winner
    ldr     r0, [r0]
    cmp     r0, #1
    beq     show_p1_win

    /* CPU won: "CPU GANA!" at (38, 22) */
    movs    r0, #38
    movs    r1, #22
    ldr     r2, =str_cpu_wins
    bl      fb_draw_string
    b       show_final_score

show_p1_win:
    /* Player won: "HAS GANADO!" at (32, 22) */
    movs    r0, #32
    movs    r1, #22
    ldr     r2, =str_p1_wins
    bl      fb_draw_string

show_final_score:
    /* Final Score: "P1: X  CPU: Y" at (26, 34) */
    movs    r0, #26
    movs    r1, #34
    ldr     r2, =str_final_p1
    bl      fb_draw_string

    movs    r0, #46
    movs    r1, #34
    ldr     r2, =score_p1
    ldr     r2, [r2]
    bl      fb_draw_number

    movs    r0, #66
    movs    r1, #34
    ldr     r2, =str_final_cpu
    bl      fb_draw_string

    movs    r0, #92
    movs    r1, #34
    ldr     r2, =score_cpu
    ldr     r2, [r2]
    bl      fb_draw_number

    /* Prompt "PULSE Z REINICIAR" at (14, 48) */
    movs    r0, #14
    movs    r1, #48
    ldr     r2, =str_restart
    bl      fb_draw_string

    /* Push Game Over Screen to OLED */
    bl      oled_flush

gameover_wait_button:
    /* Check Button Z to Restart */
    bl      read_button_z
    cmp     r0, #1
    beq     gameover_do_restart

    /* Wait a short moment */
    movs    r0, #100
delay_poll:
    subs    r0, r0, #1
    bne     delay_poll
    b       gameover_wait_button

gameover_do_restart:
    /* Wait for button release */
wait_release_restart:
    bl      read_button_z
    cmp     r0, #1
    beq     wait_release_restart

    /* Reinitialize state variables and return to Menu */
    ldr     r0, =score_p1
    movs    r1, #0
    str     r1, [r0]
    ldr     r0, =score_cpu
    str     r1, [r0]
    ldr     r0, =winner
    str     r1, [r0]

    /* Restart hardware timer */
    bl      timer_start

    /* Transition back to Menu */
    ldr     r0, =game_state
    movs    r1, #STATE_MENU
    str     r1, [r0]

    b       master_game_loop

    .end
