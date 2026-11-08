# Videojuego Pong en Ensamblador ARM Bare-Metal para Raspberry Pi Pico

Proyecto desarrollado para el curso de **Arquitectura de Computadores II**.
Implementación 100% en lenguaje ensamblador ARMv6-M (Cortex-M0+) para el microcontrolador RP2040 sin intervención de sistemas operativos ni SDK.

---

## Hardware Soportado y Conexiones

* **Tarjeta:** Raspberry Pi Pico H (RP2040)
* **Pantalla:** OLED 128x64 1.3" I2C SH1106
  * **SCL** $\rightarrow$ **GP5** (Pin 7)
  * **SDA** $\rightarrow$ **GP4** (Pin 6)
  * **VCC** $\rightarrow$ **3V3(OUT)** (Pin 36)
  * **GND** $\rightarrow$ **GND** (Pin 38)
* **Joystick:** Módulo KY-023
  * **VRX** $\rightarrow$ **GP26** (ADC0 / Pin 31)
  * **VRY** $\rightarrow$ **GP27** (ADC1 / Pin 32)
  * **SW (Botón Z)** $\rightarrow$ **GP14** (Pin 19, entrada digital con Pull-Up interna)
  * **+5V / VCC** $\rightarrow$ **3V3(OUT)** (Pin 36)
  * **GND** $\rightarrow$ **GND** (Pin 38)

---

## Estructura de Módulos (.s)

* [`boot2.s`](boot2.s): Cargador de segunda etapa (256 bytes) para arranque continuo QSPI.
* [`crt0.s`](crt0.s): Tabla de vectores Cortex-M0+, Reset Handler, inicialización de datos y pila.
* [`system.s`](system.s): Inicialización del oscilador de cristal XOSC (12MHz), árbol de relojes (`CLK_REF`, `CLK_SYS`, `CLK_PERI`, `CLK_ADC`), generador de tick de microsegundo del Watchdog, liberación de resets y LED indicador (GP25).
* [`timer.s`](timer.s): Temporizador por hardware RP2040 (ALARM0) e interrupciones NVIC a 60 FPS.
* [`inputs.s`](inputs.s): Lectura directa por registros de ADC (VRX/VRY) y SIO GPIO14 (Botón Z) con timeouts a prueba de fallos.
* [`video.s`](video.s): Controlador I2C0 Synopsys DesignWare con auto-detección (0x3C/0x3D), secuencia universal SH1106/SSD1306 y Framebuffer de 1024 bytes.
* [`font.s`](font.s): Mapa tipográfico 5x7 para renderizado de texto y marcadores.
* [`main.s`](main.s): Máquina de estados (`MENU`, `PLAYING`, `GAMEOVER`), física de colisiones y HUD.
* [`memmap.ld`](memmap.ld): Linker Script bare-metal para RP2040.
* [`REPORTE_TECNICO.md`](REPORTE_TECNICO.md): Reporte técnico académico completo (Entregable E2).

---

## Cómo Compilar y Flashear

1. Conecta la Pico a la PC con el botón **BOOTSEL** presionado (aparece la unidad `RPI-RP2`).
2. Ejecuta en terminal:
   ```cmd
   build.bat
   ```
3. El script compilará todo el ensamblador, generará `pong.uf2` y lo transferirá a la Pico.

