# Tap Orbit — Arcade Balance & UX Upgrade Plan

## Objetivo

Convertir **Tap Orbit** en un arcade móvil más adictivo, claro y jugable, sin volverlo injusto ni caótico.

La prioridad no es solo agregar efectos, sino mejorar el **game feel**:

- Que el jugador entienda qué está pasando.
- Que sienta progreso visible.
- Que el juego suba de intensidad de forma clara.
- Que la velocidad sea retadora, pero no imposible.
- Que cada partida tenga momentos memorables: combo alto, última vida, golden target, milestone, recuperación.

---

## Diagnóstico actual

El juego ya tiene una base sólida:

- Mecánica de timing clara: tocar cuando el planeta entra en el gate.
- Visual pixel art HD.
- Score.
- Vidas.
- Combo básico.
- Planetas progresivos.
- Partículas.
- Fondo espacial.
- Música/SFX preparados o en proceso.
- Estrellas/cometas ambientales.

Pero todavía hay dos problemas principales:

### 1. El gate puede sentirse demasiado estático

Si el portal siempre está en la misma posición, el loop se percibe como:

```text
esperar → tocar arriba → repetir
```

Aunque haya planetas moviéndose, el cerebro del jugador siente que el objetivo no cambia.

### 2. La velocidad puede escalar demasiado rápido

Si los planetas aceleran agresivamente, el juego pasa de divertido a imposible.

Un arcade adictivo no debe sentirse aleatorio ni injusto. Debe sentirse como:

```text
fallé porque me faltó timing, no porque el juego se volvió imposible
```

---

## Dirección de diseño

La solución ideal es una progresión por fases.

El juego debe empezar simple, enseñar la mecánica y después introducir dificultad de forma visible.

```text
ORBIT       → aprender
DRIFT       → el objetivo cambia
FLUX        → el gate se mueve
STORM       → más presión visual
SINGULARITY → caos controlado
```

---

# 1. Gate dinámico progresivo

## Problema

Un gate fijo comunica bien la mecánica, pero después de algunos puntos se siente repetitivo.

## Solución

El gate debe estar fijo al inicio y volverse dinámico por milestones.

## Fases recomendadas

| Score | Fase | Comportamiento del gate |
|---:|---|---|
| 0–24 | ORBIT | Gate fijo arriba |
| 25–74 | DRIFT | Gate cambia de posición después de cada hit |
| 75–149 | FLUX | Gate puede aparecer en diagonales |
| 150–299 | STORM | Gate rota lentamente |
| 300+ | SINGULARITY | Gate rota y puede cambiar dirección |

## Reglas UX

El gate no debe moverse desde el inicio.

Primero el jugador debe entender:

```text
Toca cuando el planeta entra en el arco brillante.
```

Después el juego puede evolucionar:

```text
Ahora el arco también se mueve.
```

## Gate visualmente vivo desde el inicio

Aunque el gate sea fijo al principio, debe sentirse vivo con:

- Pulso sutil.
- Pixeles flotando alrededor.
- Glow que respira.
- Mini partículas que entran hacia el arco.
- Pequeña flecha pixelada que late.

---

# 2. Ajuste de velocidad de planetas

## Objetivo

La velocidad debe permitir que el jugador entre en flow.

La dificultad debe subir, pero con control.

## Problema actual

Si la velocidad sube 10% cada 3 hits sin límites claros, el juego puede volverse injusto muy rápido.

## Nueva filosofía de velocidad

La velocidad debe depender de tres cosas:

```text
fase del juego + cantidad de planetas + score actual
```

No solo de hits acumulados.

---

## Velocidad base recomendada

Actualmente los planetas pueden iniciar alrededor de:

```text
0.95 + index * 0.18
```

Esto puede sentirse bien para el primer planeta, pero al agregar varios planetas y aumentar velocidad se puede volver pesado.

### Nueva propuesta

```dart
baseSpeed = 0.72 + index * 0.12
```

| Planeta | Velocidad inicial sugerida |
|---:|---:|
| 1 | 0.72 |
| 2 | 0.84 |
| 3 | 0.96 |
| 4 | 1.08 |

Esto hace que el primer minuto sea más jugable.

---

## Escalado recomendado

En lugar de subir 10% cada 3 hits durante toda la partida, usar escalado controlado:

```text
Cada 5 hits: +4% velocidad
Cada milestone: +6% adicional
Máximo global: 2.35x de la velocidad base
```

## Fórmula recomendada

```dart
speedMultiplier = min(2.35, 1.0 + totalHits * 0.008 + milestoneTier * 0.06);
```

Esto evita que el juego se vuelva imposible.

---

## Límites de velocidad

Cada planeta debería tener un `maxSpeed`.

```dart
maxSpeed = 2.25 + index * 0.15;
```

| Planeta | Max speed sugerida |
|---:|---:|
| 1 | 2.25 |
| 2 | 2.40 |
| 3 | 2.55 |
| 4 | 2.70 |

Esto mantiene el caos bajo control.

---

## Regla de oro

Nunca permitas que la dificultad escale más rápido que la capacidad visual del jugador para leer el gate.

El juego debe castigar mal timing, no mala legibilidad.

---

# 3. Combo tiers escalados

## Problema

Un solo combo x2 se queda corto.

## Solución

Agregar tiers:

| Streak | Tier | Multiplier |
|---:|---|---:|
| 0–2 | Stable | x1 |
| 3–6 | Charged | x2 |
| 7–12 | Overdrive | x3 |
| 13–20 | Hyper | x4 |
| 21+ | Max Orbit | x5 |

## Scoring recomendado

```text
Hit normal = 1 × multiplier
Perfect = hit normal + 1
Golden = hit normal × 3
Last life bonus = +1
```

## Feedback visual

Cada tier debe tener:

- Color.
- Pulso.
- Texto.
- Partículas extra.
- SFX de tier-up.

Ejemplo:

```text
COMBO x3
OVERDRIVE
```

## Al romper combo alto

Si el jugador rompe un combo x3 o superior:

```text
COMBO SHATTER
```

Con:

- Flash rojo/morado.
- Partículas quebradas.
- SFX de ruptura.
- Pequeño freeze visual falso.

---

# 4. Milestones nombrados

## Objetivo

El jugador debe sentir que el juego evoluciona.

## Fases recomendadas

| Score | Nombre | Cambio |
|---:|---|---|
| 0 | ORBIT | Tutorial natural |
| 25 | DRIFT | Gate cambia posición |
| 75 | FLUX | Gate diagonales / movimiento leve |
| 150 | STORM | Gate rota lentamente + más partículas |
| 300 | SINGULARITY | Rotación más agresiva + golden targets más frecuentes |

## Anuncio visual

Cuando se cruza un milestone:

```text
ENTERING FLUX
GATE IS SHIFTING
```

Efectos:

- Texto grande al centro.
- Flash suave.
- Pulso del gate.
- Partículas.
- Breve sensación de impacto visual.

Evitar slow motion real al inicio. Es mejor hacer un “fake dramatic pause” visual para no romper el game loop.

---

# 5. Adrenaline Mode

## Activación

Se activa cuando el jugador alcanza combo x4 o superior.

```text
comboStreak >= 13
```

## Efectos

- Vignette del color del planeta activo.
- HUD pulsando.
- Gate con brillo más intenso.
- Más partículas en los hits.
- Texto de combo más agresivo.

## Importante

No cambiar la música todavía.

El cue visual es suficiente y evita meter bugs en audio.

---

# 6. Last Life Drama

## Problema

Cuando queda 1 vida, actualmente solo estás cerca de perder. Falta drama y esperanza.

## Solución

Cuando queda una vida:

```text
LAST LIFE
```

Activar:

- Vignette rojo pulsante.
- Score bonus +1 por hit.
- Feedback visual más tenso.
- Gate más brillante.
- Partículas rojas sutiles en los bordes.

## Resurrection

Si el jugador logra una racha en última vida:

```text
8 hits seguidos en last life → RESURRECTION
```

Efecto:

- Recupera 1 vida.
- Texto grande: `RESURRECTION`
- Flash blanco/dorado.
- Partículas radiales.
- SFX especial.

## Por qué 8 y no 10

10 puede ser muy difícil para jugadores nuevos.

Se recomienda empezar con 8 y ajustar después del playtesting.

---

# 7. Golden target

## Activación

A partir de score 100:

```text
6% de probabilidad
```

A partir de SINGULARITY:

```text
10% de probabilidad
```

## Comportamiento

El target activo se vuelve dorado temporalmente.

No debe agregarse un nuevo planeta. Solo se modifica el planeta objetivo actual.

## Reglas

```text
Golden hit = 3x puntos
Golden perfect = 3x puntos + bonus visual
Golden miss = pierde vida normal
```

## Balance

El golden target debe tener una ventana más estrecha:

```dart
goldenHitWindow = hitWindow * 0.72;
goldenPerfectWindow = perfectWindow * 0.70;
```

## Feedback

Al acertar:

```text
GOLDEN!
```

Con:

- Burst dorado.
- Flash cálido.
- SFX brillante.
- Score popup.

---

# 8. Ambiente vivo

## Estado deseado

El fondo no debe sentirse decorativo solamente. Debe sentirse vivo.

## Elementos

- Estrellas que respiran.
- Polvo espacial flotando.
- Planetas decorativos con glow pulsante.
- Motes orbitando planetas decorativos.
- Estrellas fugaces más frecuentes.
- Cometas cruzando desde diferentes bordes del mapa.

## Frecuencia de cometas

Recomendado:

```dart
initialCooldown = 1.8 + random * 3.2;
nextCooldown = 2.2 + random * 4.2;
```

Esto hace que se vean más seguido sin saturar.

## Spawn de cometas

No deben salir siempre del mismo punto.

Deben poder cruzar desde:

```text
izquierda → derecha
derecha → izquierda
arriba → abajo
abajo → arriba
diagonal variable
```

---

# 9. Audio recomendado

## Eventos

| Evento | Sonido |
|---|---|
| Tap | Blip corto |
| Hit | Ping brillante |
| Perfect | Sparkle más alto |
| Miss | Buzz bajo |
| Combo tier-up | Power-up |
| Combo shatter | Break/glitch |
| Game over | Pitch down |
| Resurrection | Rise/chime |
| Golden hit | Crystal shine |

## Nota

El audio debe reforzar la acción, no distraer.

Para este juego, sonidos cortos y limpios funcionan mejor que sonidos largos.

---

# 10. Balance final recomendado

## Velocidad

```text
Base speed más baja
Escalado más lento
Cap máximo por planeta
No más +10% cada 3 hits sin límite
```

## Gate

```text
Fijo al inicio
Después cambia de posición
Después rota
Después rota con más intensidad
```

## Puntos

```text
Combo tiers claros
Perfect bonus
Golden multiplier
Last life bonus
```

## Dificultad

La dificultad debe sentirse como una escalera, no como una pared.

---

# 11. Orden de implementación recomendado

## Fase 1 — Jugabilidad

1. Ajustar velocidad base.
2. Agregar caps de velocidad.
3. Agregar combo tiers.
4. Agregar last life drama.

## Fase 2 — Progresión

5. Agregar milestones.
6. Agregar gate dinámico progresivo.
7. Agregar milestone announcements.

## Fase 3 — Juice

8. Agregar golden target.
9. Agregar adrenaline mode.
10. Agregar combo shatter.
11. Mejorar SFX por evento.

## Fase 4 — Polish visual

12. Cometas más frecuentes.
13. Más vida ambiental.
14. Mejor Game Over screen.
15. Mejor onboarding inicial.

---

# 12. Criterios de éxito

El juego se considera mejor balanceado si:

- El jugador nuevo puede llegar a score 25 en pocas partidas.
- Score 75 se siente alcanzable pero retador.
- Score 150 se siente como una partida buena.
- Score 300 se siente como high skill.
- La pérdida se siente justa.
- El jugador entiende por qué falló.
- El jugador quiere jugar otra vez inmediatamente.

---

# 13. Resumen ejecutivo

La propuesta es buena y debe implementarse, pero con cuidado en la velocidad.

La clave es:

```text
más movimiento visual
más progresión visible
más recompensas por habilidad
más drama cuando casi pierdes
menos escalado injusto de velocidad
```

El cambio más importante para que sea jugable:

```text
bajar velocidad base y controlar el escalado
```

El cambio más importante para que sea adictivo:

```text
combo tiers + milestones + last life resurrection
```

El cambio más importante para que se sienta vivo:

```text
gate dinámico progresivo + ambiente animado
```

---

## Decisión recomendada

Implementar las 5 mejoras principales, pero con estos ajustes:

```text
- Score milestones más tempranos: 25, 75, 150, 300
- Gate fijo solo durante ORBIT
- Velocidad base reducida
- Escalado por hits más suave
- Cap máximo por planeta
- Resurrection a 8 hits en last life
- Golden chance inicial de 6%
```

Esto mantiene Tap Orbit como un juego arcade simple, pero mucho más adictivo y justo.
