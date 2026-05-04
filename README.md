# Local Speech Service

Servicio local y ligero de text-to-speech usando Kokoro y transcripcion de audio usando Whisper.

## Requisitos

- Python 3.11 o 3.12
- `espeak-ng` instalado en el sistema para varios idiomas, incluido espanol.

En Windows, la forma mas sencilla suele ser instalar `espeak-ng` y asegurarte de que el ejecutable queda en el `PATH`.
El instalador de Windows intenta instalar automaticamente Python 3.12 y `espeak-ng` usando `winget` o Chocolatey si no los encuentra.
En Linux, el instalador tambien intenta instalar Python 3.11/3.12, el modulo `venv` y `espeak-ng` usando el gestor de paquetes disponible (`apt`, `dnf`, `yum`, `pacman`, `zypper` o `apk`).

## Instalacion

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Desde `cmd.exe`:

```bat
scripts\install.bat
```

Linux:

```bash
chmod +x scripts/*.sh
./scripts/install.sh
```

Si ya tienes Python y `espeak-ng` instalados o prefieres instalar dependencias de sistema a mano:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -SkipSystemDeps
```

Desde `cmd.exe`:

```bat
scripts\install.bat -SkipSystemDeps
```

```bash
SKIP_SYSTEM_DEPS=1 ./scripts/install.sh
```

La primera generacion puede tardar porque Kokoro descarga o prepara los pesos del modelo.
La primera transcripcion tambien puede tardar porque Whisper descarga el modelo local. Por defecto usa `tiny`; puedes cambiarlo con la variable de entorno `WHISPER_MODEL`, por ejemplo `small`, `medium` o `large-v3`.

## Ejecutar

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

Desde `cmd.exe`:

```bat
scripts\start.bat
```

En Linux:

```bash
./scripts/start.sh
```

Abre:

```text
http://127.0.0.1:8000
```

Por defecto el servicio solo escucha en `127.0.0.1`, asi que no acepta conexiones desde otros equipos.
Para exponerlo en tu red local, detenlo y arrancalo escuchando en todas las interfaces:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1 -BindHost 0.0.0.0
```

Desde `cmd.exe`:

```bat
scripts\stop.bat
scripts\start.bat -BindHost 0.0.0.0
```

Tambien puedes usar el acceso directo:

```bat
scripts\start-lan.bat
```

En Linux:

```bash
./scripts/stop.sh
SPEECH_HOST=0.0.0.0 ./scripts/start.sh
```

Entonces, desde otro equipo de la misma red, abre la IP LAN del equipo servidor:

```text
http://192.168.10.205:8000
```

Si sigue sin responder, revisa que el firewall del sistema permita conexiones entrantes TCP al puerto `8000`.

Para detenerlo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop.ps1
```

Desde `cmd.exe`:

```bat
scripts\stop.bat
```

En Linux:

```bash
./scripts/stop.sh
```

Tambien puedes ejecutarlo en primer plano para ver los logs:

```powershell
.\.venv\Scripts\uvicorn.exe app.main:app --host 127.0.0.1 --port 8000
```

Para verlo desde otros equipos en la red local:

```powershell
.\.venv\Scripts\uvicorn.exe app.main:app --host 0.0.0.0 --port 8000
```

En Linux:

```bash
./.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Para verlo desde otros equipos en la red local:

```bash
./.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## API

Llamadas sin parametros:

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8000/tts
```

```powershell
Invoke-RestMethod `
  -Uri http://127.0.0.1:8000/tts `
  -Method POST `
  -ContentType "application/json" `
  -Body '{}'
```

Si llamas a `/tts` o `/v1/audio/speech` sin `text`/`input`, el servicio responde con JSON explicando los campos requeridos, ejemplos de payload, limites, idiomas, voces y endpoints de metadata. Esto esta pensado para clientes automaticos y bots que descubren el API sin documentacion externa.

Para obtener audio hay dos modos:

- Enviar `text` a `/tts` sin `save` devuelve directamente bytes `audio/wav`. El cliente debe guardar el cuerpo de la respuesta como `.wav`.
- Enviar `text` a `/tts` con `"save": true` guarda el WAV en el servidor y devuelve JSON con `filename`, `download_url` y `content_type`. Un bot debe resolver `download_url` contra el origen del servicio. Por ejemplo, si llamo a `http://192.168.10.205:8000/tts` y recibo `/audio/speech-...wav`, la descarga completa es `http://192.168.10.205:8000/audio/speech-...wav`.

Generar WAV:

```powershell
Invoke-WebRequest `
  -Uri http://127.0.0.1:8000/tts `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"text":"Hola, esto es una prueba local.","lang_code":"e","voice":"ef_dora","speed":1.0}' `
  -OutFile output.wav
```

Generar WAV y obtener una URL descargable desde cualquier equipo que pueda acceder al servicio:

```powershell
Invoke-RestMethod `
  -Uri http://127.0.0.1:8000/tts `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"text":"Hola, esto queda disponible para descarga.","lang_code":"e","voice":"ef_dora","speed":1.0,"save":true}'
```

La respuesta incluye `download_url`, por ejemplo `/audio/speech-...wav`. Si el servicio esta expuesto en la LAN, el fichero se descarga usando:

```text
http://192.168.10.205:8000/audio/speech-...wav
```

Endpoint compatible estilo OpenAI:

```powershell
Invoke-WebRequest `
  -Uri http://127.0.0.1:8000/v1/audio/speech `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"model":"kokoro","input":"Hello from Kokoro.","voice":"af_heart","lang_code":"a","speed":1.0}' `
  -OutFile speech.wav
```

Transcribir audio:

```powershell
Invoke-RestMethod `
  -Uri http://127.0.0.1:8000/transcribe `
  -Method POST `
  -Form @{
    file = Get-Item .\audio.wav
    language = "es"
  }
```

Endpoint de transcripcion compatible estilo OpenAI:

```powershell
Invoke-RestMethod `
  -Uri http://127.0.0.1:8000/v1/audio/transcriptions `
  -Method POST `
  -Form @{
    file = Get-Item .\audio.wav
    model = "whisper"
    language = "es"
    response_format = "json"
  }
```

Para recibir solo texto:

```powershell
Invoke-RestMethod `
  -Uri http://127.0.0.1:8000/transcribe `
  -Method POST `
  -Form @{
    file = Get-Item .\audio.wav
    response_format = "text"
  }
```

Codigos utiles de idioma:

- `a`: ingles americano
- `b`: ingles britanico
- `e`: espanol
- `f`: frances
- `h`: hindi
- `i`: italiano
- `j`: japones
- `p`: portugues brasileno
- `z`: chino mandarin

## Voces disponibles

La voz debe corresponder normalmente con el `lang_code`. Por ejemplo, `ef_dora` usa `e` para espanol y `af_heart` usa `a` para ingles americano.

| Idioma | `lang_code` | Voces |
| --- | --- | --- |
| Ingles americano, femenino | `a` | `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky` |
| Ingles americano, masculino | `a` | `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`, `am_santa` |
| Ingles britanico, femenino | `b` | `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily` |
| Ingles britanico, masculino | `b` | `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis` |
| Espanol, femenino | `e` | `ef_dora` |
| Espanol, masculino | `e` | `em_alex`, `em_santa` |
| Frances, femenino | `f` | `ff_siwis` |
| Hindi, femenino | `h` | `hf_alpha`, `hf_beta` |
| Hindi, masculino | `h` | `hm_omega`, `hm_psi` |
| Italiano, femenino | `i` | `if_sara` |
| Italiano, masculino | `i` | `im_nicola` |
| Japones, femenino | `j` | `jf_alpha`, `jf_gongitsune`, `jf_nezumi`, `jf_tebukuro` |
| Japones, masculino | `j` | `jm_kumo` |
| Portugues brasileno, femenino | `p` | `pf_dora` |
| Portugues brasileno, masculino | `p` | `pm_alex`, `pm_santa` |
| Chino mandarin, femenino | `z` | `zf_xiaobei`, `zf_xiaoni`, `zf_xiaoxiao`, `zf_xiaoyi` |
| Chino mandarin, masculino | `z` | `zm_yunjian`, `zm_yunxi`, `zm_yunxia`, `zm_yunyang` |
