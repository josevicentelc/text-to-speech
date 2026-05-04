from __future__ import annotations

from io import BytesIO
from threading import Lock
from typing import Literal

import numpy as np
import soundfile as sf
from fastapi import Body, FastAPI, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import HTMLResponse, JSONResponse, Response
from kokoro import KPipeline
from pydantic import BaseModel, Field


SAMPLE_RATE = 24_000
DEFAULT_LANG_CODE = "e"
DEFAULT_VOICE = "ef_dora"

LANGUAGES = {
    "a": "English, American",
    "b": "English, British",
    "e": "Spanish",
    "f": "French",
    "h": "Hindi",
    "i": "Italian",
    "j": "Japanese",
    "p": "Brazilian Portuguese",
    "z": "Mandarin Chinese",
}

COMMON_VOICES = {
    "a": [
        "af_alloy",
        "af_aoede",
        "af_bella",
        "af_heart",
        "af_jessica",
        "af_kore",
        "af_nicole",
        "af_nova",
        "af_river",
        "af_sarah",
        "af_sky",
        "am_adam",
        "am_echo",
        "am_eric",
        "am_fenrir",
        "am_liam",
        "am_michael",
        "am_onyx",
        "am_puck",
        "am_santa",
    ],
    "b": ["bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis"],
    "e": ["ef_dora", "em_alex", "em_santa"],
    "f": ["ff_siwis"],
    "h": ["hf_alpha", "hf_beta", "hm_omega", "hm_psi"],
    "i": ["if_sara", "im_nicola"],
    "j": ["jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo"],
    "p": ["pf_dora", "pm_alex", "pm_santa"],
    "z": [
        "zf_xiaobei",
        "zf_xiaoni",
        "zf_xiaoxiao",
        "zf_xiaoyi",
        "zm_yunjian",
        "zm_yunxi",
        "zm_yunxia",
        "zm_yunyang",
    ],
}


class TTSRequest(BaseModel):
    text: str | None = Field(default=None, min_length=1, max_length=10_000)
    lang_code: str = Field(default=DEFAULT_LANG_CODE, min_length=1, max_length=4)
    voice: str = Field(default=DEFAULT_VOICE, min_length=1, max_length=120)
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    split_pattern: str = Field(default=r"\n+", max_length=120)
    format: Literal["wav"] = "wav"


class OpenAISpeechRequest(BaseModel):
    model: str = "kokoro"
    input: str | None = Field(default=None, min_length=1, max_length=10_000)
    voice: str = Field(default=DEFAULT_VOICE, min_length=1, max_length=120)
    lang_code: str = Field(default=DEFAULT_LANG_CODE, min_length=1, max_length=4)
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    response_format: Literal["wav"] = "wav"


app = FastAPI(
    title="Local Kokoro TTS",
    version="0.1.0",
    description="Servicio local y ligero para convertir texto en voz con Kokoro.",
)

_pipelines: dict[str, KPipeline] = {}
_pipeline_lock = Lock()


def get_pipeline(lang_code: str) -> KPipeline:
    normalized = lang_code.strip().lower()
    if normalized not in LANGUAGES:
        raise HTTPException(status_code=400, detail=f"Unsupported lang_code: {lang_code}")

    with _pipeline_lock:
        pipeline = _pipelines.get(normalized)
        if pipeline is None:
            pipeline = KPipeline(lang_code=normalized)
            _pipelines[normalized] = pipeline
        return pipeline


def synthesize_wav(request: TTSRequest) -> bytes:
    if request.text is None:
        raise HTTPException(status_code=400, detail="Missing required field: text")

    pipeline = get_pipeline(request.lang_code)
    chunks = []

    try:
        generator = pipeline(
            request.text,
            voice=request.voice,
            speed=request.speed,
            split_pattern=request.split_pattern,
        )
        for _, _, audio in generator:
            chunks.append(np.asarray(audio, dtype=np.float32))
    except Exception as exc:  # Kokoro surfaces dependency/model issues as generic exceptions.
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    if not chunks:
        raise HTTPException(status_code=422, detail="Kokoro did not produce audio for this text.")

    audio = np.concatenate(chunks)
    buffer = BytesIO()
    sf.write(buffer, audio, SAMPLE_RATE, format="WAV")
    return buffer.getvalue()


def wav_response(audio: bytes) -> Response:
    return Response(
        content=audio,
        media_type="audio/wav",
        headers={"Content-Disposition": 'inline; filename="speech.wav"'},
    )


def api_help() -> dict[str, object]:
    return {
        "service": "Local Kokoro TTS",
        "description": "Convert text to speech locally. Valid synthesis requests return audio/wav.",
        "quick_start": {
            "endpoint": "POST /tts",
            "content_type": "application/json",
            "required_fields": ["text"],
            "optional_fields": {
                "lang_code": DEFAULT_LANG_CODE,
                "voice": DEFAULT_VOICE,
                "speed": 1.0,
                "split_pattern": r"\n+",
                "format": "wav",
            },
            "example_request": {
                "text": "Hola, esto es una prueba local.",
                "lang_code": "e",
                "voice": "ef_dora",
                "speed": 1.0,
            },
        },
        "openai_compatible": {
            "endpoint": "POST /v1/audio/speech",
            "content_type": "application/json",
            "required_fields": ["input"],
            "optional_fields": {
                "model": "kokoro",
                "voice": DEFAULT_VOICE,
                "lang_code": DEFAULT_LANG_CODE,
                "speed": 1.0,
                "response_format": "wav",
            },
            "example_request": {
                "model": "kokoro",
                "input": "Hello from Kokoro.",
                "voice": "af_heart",
                "lang_code": "a",
                "speed": 1.0,
            },
        },
        "limits": {
            "max_text_length": 10_000,
            "speed_min": 0.5,
            "speed_max": 2.0,
            "sample_rate": SAMPLE_RATE,
            "audio_format": "wav",
        },
        "metadata_endpoints": {
            "health": "GET /health",
            "voices": "GET /voices",
            "docs": "GET /docs",
        },
        "languages": LANGUAGES,
        "voices": COMMON_VOICES,
    }


def help_response() -> JSONResponse:
    return JSONResponse(api_help())


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return """
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Kokoro TTS Local</title>
  <style>
    :root { color-scheme: light dark; font-family: Inter, Segoe UI, system-ui, sans-serif; }
    body { margin: 0; background: #f7f4ef; color: #171717; }
    main { max-width: 780px; margin: 0 auto; padding: 32px 18px; }
    h1 { margin: 0 0 18px; font-size: clamp(2rem, 5vw, 3.5rem); letter-spacing: 0; }
    label { display: grid; gap: 6px; margin: 14px 0; font-weight: 650; }
    textarea, input, select, button {
      border: 1px solid #b8b2a7; border-radius: 8px; font: inherit; padding: 10px 12px;
      background: #fffefa; color: #171717;
    }
    textarea { min-height: 180px; resize: vertical; }
    .grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }
    button { cursor: pointer; background: #116466; color: white; border-color: #116466; font-weight: 700; }
    button:disabled { opacity: .65; cursor: wait; }
    audio { width: 100%; margin-top: 18px; }
    @media (max-width: 680px) { .grid { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <main>
    <h1>Kokoro TTS Local</h1>
    <label>Texto
      <textarea id="text">Hola, soy Kokoro corriendo como servicio local.</textarea>
    </label>
    <div class="grid">
      <label>Idioma
        <select id="lang">
          <option value="e" selected>Espanol</option>
          <option value="a">English US</option>
          <option value="b">English UK</option>
          <option value="f">Francais</option>
          <option value="i">Italiano</option>
          <option value="p">Portugues BR</option>
        </select>
      </label>
      <label>Voz
        <input id="voice" value="ef_dora">
      </label>
      <label>Velocidad
        <input id="speed" type="number" min="0.5" max="2" step="0.1" value="1">
      </label>
    </div>
    <button id="speak">Generar voz</button>
    <audio id="audio" controls></audio>
  </main>
  <script>
    const voiceByLang = { e: "ef_dora", a: "af_heart", b: "bf_emma", f: "ff_siwis", i: "if_sara", p: "pf_dora" };
    lang.addEventListener("change", () => { voice.value = voiceByLang[lang.value] || voice.value; });
    speak.addEventListener("click", async () => {
      speak.disabled = true;
      try {
        const response = await fetch("/tts", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: text.value, lang_code: lang.value, voice: voice.value, speed: Number(speed.value) })
        });
        if (!response.ok) throw new Error(await response.text());
        const blob = await response.blob();
        audio.src = URL.createObjectURL(blob);
        await audio.play();
      } catch (error) {
        alert(error.message);
      } finally {
        speak.disabled = false;
      }
    });
  </script>
</body>
</html>
    """


@app.get("/health")
def health() -> dict[str, object]:
    return {"ok": True, "sample_rate": SAMPLE_RATE, "loaded_languages": sorted(_pipelines)}


@app.get("/voices")
def voices() -> dict[str, object]:
    return {"languages": LANGUAGES, "voices": COMMON_VOICES}


@app.get("/tts")
def tts_help() -> JSONResponse:
    return help_response()


@app.post("/tts")
async def tts(request: TTSRequest | None = Body(default=None)) -> Response:
    if request is None or request.text is None:
        return help_response()

    audio = await run_in_threadpool(synthesize_wav, request)
    return wav_response(audio)


@app.get("/v1/audio/speech")
def openai_speech_help() -> JSONResponse:
    return help_response()


@app.post("/v1/audio/speech")
async def openai_speech(request: OpenAISpeechRequest | None = Body(default=None)) -> Response:
    if request is None or request.input is None:
        return help_response()

    if request.model != "kokoro":
        raise HTTPException(status_code=400, detail="Only the local 'kokoro' model is supported.")

    audio = await run_in_threadpool(
        synthesize_wav,
        TTSRequest(
            text=request.input,
            lang_code=request.lang_code,
            voice=request.voice,
            speed=request.speed,
            format=request.response_format,
        ),
    )
    return wav_response(audio)
