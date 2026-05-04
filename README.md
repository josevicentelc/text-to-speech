# Local Kokoro TTS Service

Servicio local y ligero de text-to-speech usando Kokoro.

## Requisitos

- Python 3.11 o 3.12
- `espeak-ng` instalado en el sistema para varios idiomas, incluido espanol.

En Windows, la forma mas sencilla suele ser instalar `espeak-ng` y asegurarte de que el ejecutable queda en el `PATH`.

## Instalacion

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Linux:

```bash
chmod +x scripts/*.sh
./scripts/install.sh
```

Si ya tienes `espeak-ng` instalado o prefieres instalar dependencias de sistema a mano:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -SkipSystemDeps
```

```bash
SKIP_SYSTEM_DEPS=1 ./scripts/install.sh
```

La primera generacion puede tardar porque Kokoro descarga o prepara los pesos del modelo.

## Ejecutar

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

En Linux:

```bash
./scripts/start.sh
```

Abre:

```text
http://127.0.0.1:8000
```

Para detenerlo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop.ps1
```

En Linux:

```bash
./scripts/stop.sh
```

Tambien puedes ejecutarlo en primer plano para ver los logs:

```powershell
.\.venv\Scripts\uvicorn.exe app.main:app --host 127.0.0.1 --port 8000
```

En Linux:

```bash
./.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
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

Generar WAV:

```powershell
Invoke-WebRequest `
  -Uri http://127.0.0.1:8000/tts `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"text":"Hola, esto es una prueba local.","lang_code":"e","voice":"ef_dora","speed":1.0}' `
  -OutFile output.wav
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
