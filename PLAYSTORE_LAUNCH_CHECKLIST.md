# Tap Orbit - Checklist para publicar en Google Play

Fecha de corte: 2026-04-27

## Estado actual del proyecto

- Nombre visible: `Tap Orbit`
- Package name / applicationId: `com.requiemf18.taporbit`
- Version actual: `1.0.0+1`
- `versionName`: `1.0.0`
- `versionCode`: `1`
- `compileSdk`: `36`
- `targetSdk`: `35`
- `minSdk`: `24`
- Orientacion: portrait only
- Permisos sensibles: no detectados
- Permiso de Internet en release: no detectado
- Login dentro de la app: no detectado
- Ads/analytics/Firebase: no detectados
- APK release: generado correctamente en `build/app/outputs/flutter-apk/app-release.apk`
- AAB release: se genera `build/app/outputs/bundle/release/app-release.aab`, pero Flutter termina con error por el paso de strip de simbolos del toolchain Android

## Cambios ya dejados listos

- Se alineo `MainActivity` con el package real `com.requiemf18.taporbit`.
- Se subio `compileSdk` a `36` para compatibilidad con `shared_preferences_android`.
- Se dejo configurada firma de release por `key.properties`.
- Se agrego `android/key.properties.example` como plantilla.
- Se fijo `minSdk` a `24`, que coincide con el manifest mergeado efectivo del release.

## Bloqueos tecnicos actuales

### 1. Android toolchain incompleto

`flutter doctor -v` reporta:

- `cmdline-tools component is missing`
- `Android license status unknown`

Mientras eso siga asi, el build de `appbundle` puede seguir fallando al final aunque deje un `.aab` en disco.

### 2. Falta tu keystore de subida

Hoy el proyecto ya sabe leer `android/key.properties`, pero todavia falta crear tu keystore real y llenar ese archivo.

### 3. Faltan assets y metadata de Play Store

No hay en el repo:

- icono de Play Store `512x512`
- feature graphic `1024x500`
- screenshots finales para la ficha
- politica de privacidad publicada en una URL

## Lo que sigue exactamente

### Paso 1. Arreglar el entorno Android

En Android Studio:

- Abre `Tools > SDK Manager`
- Instala o actualiza:
- `Android SDK Command-line Tools`
- `Android SDK Build-Tools`
- `Android SDK Platform-Tools`
- la plataforma Android que vayas a usar

Luego corre:

```bash
flutter doctor --android-licenses
flutter doctor -v
```

No sigas al paso de publicacion hasta que `Android toolchain` salga con `✓`.

### Paso 2. Crear la llave de subida

Tienes dos caminos validos:

- Android Studio:
  `Build > Generate Signed Bundle / APK > Android App Bundle > Create new`
- Terminal con `keytool`, por ejemplo:

```bash
keytool -genkeypair -v \
  -keystore ~/keystores/tap-orbit-upload.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
```

Guarda esa `.jks` fuera del repo y respaldala.

### Paso 3. Crear `android/key.properties`

Usa la plantilla que ya te deje:

```bash
cp android/key.properties.example android/key.properties
```

Rellena valores reales:

```properties
storeFile=/ruta/absoluta/a/tu/upload-keystore.jks
storePassword=tu_password_del_keystore
keyAlias=upload
keyPassword=tu_password_de_la_key
```

`android/.gitignore` ya excluye `key.properties` y archivos `.jks`.

### Paso 4. Generar el AAB final

Comando esperado:

```bash
flutter build appbundle --release
```

Salida esperada:

- archivo final en `build/app/outputs/bundle/release/app-release.aab`

Nota:

- Hoy ya se genero ese archivo, pero Flutter termino con error por el toolchain.
- El APK release si compila bien y te sirve para pruebas manuales:

```bash
flutter build apk --release
```

### Paso 5. Crear la app en Play Console

En Play Console:

1. `Home > Create app`
2. Nombre: `Tap Orbit`
3. Tipo: `Game`
4. Precio: `Free` o `Paid`
5. Email de soporte
6. Aceptar politicas y `Play App Signing`

Importante:

- El package name debe coincidir exactamente con `com.requiemf18.taporbit`.

### Paso 6. Preparar la ficha de la tienda

Minimo practico que debes tener listo:

- App icon: PNG 32-bit con alpha, `512x512`
- Feature graphic: JPG o PNG 24-bit sin alpha, `1024x500`
- Short description: maximo `80` caracteres
- Full description
- Al menos `2` screenshots

Recomendado para tener mejor presentacion:

- `4` screenshots de al menos `1080px`
- screenshots reales del gameplay
- textos consistentes con lo que la app hace de verdad

### Paso 7. Completar App content

Con base en el codigo actual, esto es lo mas probable:

- Ads: `No`
- App access: `No login required`
- Target audience: publico general; no marcar ninos salvo que de verdad vayas por politica Families
- Content rating: completar cuestionario
- Data safety: probablemente `No data collected` y `No data shared`

Verifica esto antes de enviar:

- si agregas analytics
- si agregas ads
- si agregas login
- si agregas permisos nuevos

Sobre privacidad:

- No veo una politica de privacidad en el repo.
- Para esta app, por el estado actual, podria no ser estrictamente obligatoria si no manejas datos sensibles ni va dirigida a ninos.
- Aun asi, es muy recomendable publicar una politica simple en una URL antes de enviar.

### Paso 8. Testing antes de produccion

Recomendacion general:

- Sube primero a `Internal testing`
- Instala la app desde Play en uno o dos dispositivos reales
- Valida arranque, audio, rotacion, pausas, icono, nombre y rendimiento

Si tu cuenta es personal y fue creada despues de `2023-11-13`, Google Play hoy pide esto antes de produccion:

- closed test
- minimo `12` testers
- durante al menos `14` dias continuos
- despues solicitar acceso a produccion

Si tu cuenta personal es nueva, tambien puede pedir verificacion desde la app movil de Play Console con un dispositivo Android real.

### Paso 9. Lanzamiento a produccion

Cuando ya este todo listo:

1. Sube el `app-release.aab`
2. Agrega release notes
3. Revisa errores y warnings
4. Define paises y disponibilidad
5. Define precio si aplica
6. `Start rollout to production`

## Metadata sugerida para Tap Orbit

### Categoria sugerida

- `Game`
- subcategoria sugerida: `Arcade`

### Short description sugerida

`Juego arcade de un dedo: toca en el momento exacto y encadena combos.`

### Borrador de full description

`Tap Orbit es un juego arcade de un dedo donde varios planetas orbitan una estrella central. Toca la pantalla para disparar un anillo desde el centro y atrapa el planeta activo en el momento exacto para sumar puntos, mantener tu combo y aumentar la velocidad.`

`Mientras sobrevives con 3 vidas, el reto crece con mas planetas, mas ritmo y mas precision. Ideal para partidas cortas y para perseguir tu mejor puntuacion.`

## Checklist corto de envio

- `flutter doctor -v` sin errores en Android
- keystore creada y respaldada
- `android/key.properties` lleno
- `flutter build appbundle --release` estable
- icono 512x512 listo
- feature graphic 1024x500 lista
- screenshots listas
- short description y full description listas
- app content completado
- testing interno completado
- si aplica, closed test de 12 testers por 14 dias
- release de produccion enviada

## Archivos que debes tocar

- `android/app/build.gradle.kts`
- `android/key.properties`
- `android/key.properties.example`

## Fuentes oficiales revisadas

- Crear y configurar app:
  https://support.google.com/googleplay/android-developer/answer/9859152?hl=en
- Dashboard y tareas obligatorias:
  https://support.google.com/googleplay/android-developer/answer/9859454?hl=en
- App content / review:
  https://support.google.com/googleplay/android-developer/answer/9859455?hl=en
- Preview assets:
  https://support.google.com/googleplay/android-developer/answer/9866151?hl=en
- Firmado de apps:
  https://developer.android.com/studio/publish/app-signing
- Target API actual:
  https://support.google.com/googleplay/android-developer/answer/11926878?hl=en
- Guia tecnica target API:
  https://developer.android.com/google/play/requirements/target-sdk
- Testing para cuentas personales nuevas:
  https://support.google.com/googleplay/android-developer/answer/14151465?hl=en
- Verificacion de dispositivo para cuentas personales nuevas:
  https://support.google.com/googleplay/android-developer/answer/14316361?hl=en
- Verificacion de identidad:
  https://support.google.com/googleplay/android-developer/answer/10841920?hl=en
- Troubleshooting Flutter `cmdline-tools`:
  https://docs.flutter.dev/install/troubleshoot

