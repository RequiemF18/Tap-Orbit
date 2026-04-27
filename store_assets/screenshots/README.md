# Screenshots para Google Play Store

Pon aquí los screenshots finales del gameplay. Google Play exige mínimo **2** y permite hasta **8**.

## Especificaciones obligatorias

- Formato: **PNG** o **JPG** de 24-bit (sin alpha)
- Aspecto: **16:9** o **9:16** (vertical funciona perfecto para Tap Orbit)
- Lado mínimo: **320 px**
- Lado máximo: **3840 px**
- La proporción entre lado largo y corto no puede exceder **2:1**

## Recomendado (lo que mejor convierte)

- Resolución: **1080 × 2400** (o cualquier 9:19.5 moderno)
- Cantidad: **4–8 screenshots**
- Ningún UI del sistema (status bar y nav bar limpios — el emulador ya lo hace)
- PNG sin recortar

## Qué capturar (orden sugerido)

| # | Momento | Por qué |
|---|---|---|
| 1 | **Pantalla inicial** con el hint "TAP WHEN THE PLANET ENTERS THE GATE" | Vende el concepto del juego de un vistazo |
| 2 | **Mid-game** con score de ~10-20 y 2-3 planetas activos | Muestra escalado de dificultad |
| 3 | **Combo activo** (texto "COMBO x2 N" visible) | Muestra el sistema de recompensa |
| 4 | **Hit perfect** con partículas de explosión | Momento de máxima satisfacción visual |
| 5 (opcional) | **Game Over** con score alto | Muestra meta de high-score |
| 6 (opcional) | **Distintos planetas activos** (cyan, magenta, verde, ámbar) | Muestra variedad |

## Cómo tomarlos desde el emulador

Con la app corriendo en el emulador, usa:

```bash
ADB=/Users/alexfe/Library/Android/sdk/platform-tools/adb
$ADB exec-out screencap -p > screenshots/01_main.png
```

O directamente en el emulador: botón de cámara en la barra lateral.

## Cómo tomarlos desde un dispositivo físico

1. Conecta el celular por USB con depuración activada
2. `adb devices` debe listarlo
3. `adb exec-out screencap -p > screenshots/01_main.png`

O directamente en el celular: `Power + Volumen abajo`.

## Naming sugerido

`01_main.png`, `02_gameplay.png`, `03_combo.png`, etc. — Play Console respeta el orden alfabético al mostrarlos.
