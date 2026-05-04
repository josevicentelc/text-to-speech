from __future__ import annotations

import os
import re
import tempfile
import uuid
from io import BytesIO
from pathlib import Path
from threading import Lock
from typing import Literal

import numpy as np
import soundfile as sf
from fastapi import Body, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, PlainTextResponse, Response
from faster_whisper import WhisperModel
from kokoro import KPipeline
from pydantic import BaseModel, Field


SAMPLE_RATE = 24_000
DEFAULT_LANG_CODE = "e"
DEFAULT_VOICE = "ef_dora"
DEFAULT_WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "tiny")
DEFAULT_WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "cpu")
DEFAULT_WHISPER_COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "int8")
MAX_TRANSCRIPTION_BYTES = int(os.environ.get("MAX_TRANSCRIPTION_BYTES", str(100 * 1024 * 1024)))
GENERATED_AUDIO_DIR = Path(os.environ.get("GENERATED_AUDIO_DIR", "generated_audio")).resolve()
DOWNLOAD_FILENAME_PATTERN = re.compile(r"^speech-[a-f0-9]{32}\.wav$")

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
    save: bool = False


class OpenAISpeechRequest(BaseModel):
    model: str = "kokoro"
    input: str | None = Field(default=None, min_length=1, max_length=10_000)
    voice: str = Field(default=DEFAULT_VOICE, min_length=1, max_length=120)
    lang_code: str = Field(default=DEFAULT_LANG_CODE, min_length=1, max_length=4)
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    response_format: Literal["wav"] = "wav"


app = FastAPI(
    title="Local Speech Service",
    version="0.1.0",
    description="Servicio local y ligero para convertir texto en voz con Kokoro y transcribir audio con Whisper.",
)

_pipelines: dict[str, KPipeline] = {}
_pipeline_lock = Lock()
_whisper_model: WhisperModel | None = None
_whisper_lock = Lock()


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


def save_generated_audio(audio: bytes) -> str:
    GENERATED_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    filename = f"speech-{uuid.uuid4().hex}.wav"
    path = GENERATED_AUDIO_DIR / filename
    path.write_bytes(audio)
    return filename


def get_whisper_model() -> WhisperModel:
    global _whisper_model
    with _whisper_lock:
        if _whisper_model is None:
            _whisper_model = WhisperModel(
                DEFAULT_WHISPER_MODEL,
                device=DEFAULT_WHISPER_DEVICE,
                compute_type=DEFAULT_WHISPER_COMPUTE_TYPE,
            )
        return _whisper_model


def transcribe_file(
    path: str,
    language: str | None = None,
    task: Literal["transcribe", "translate"] = "transcribe",
    beam_size: int = 5,
) -> dict[str, object]:
    try:
        model = get_whisper_model()
        segments, info = model.transcribe(
            path,
            language=language or None,
            task=task,
            beam_size=beam_size,
            vad_filter=True,
        )
        segment_payload = [
            {"start": segment.start, "end": segment.end, "text": segment.text}
            for segment in segments
        ]
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    text = "".join(segment["text"] for segment in segment_payload).strip()
    return {
        "text": text,
        "language": info.language,
        "language_probability": info.language_probability,
        "duration": info.duration,
        "segments": segment_payload,
        "model": DEFAULT_WHISPER_MODEL,
    }


async def save_upload_to_temp(upload: UploadFile) -> str:
    suffix = os.path.splitext(upload.filename or "")[1] or ".audio"
    size = 0
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        with temp_file:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_TRANSCRIPTION_BYTES:
                    raise HTTPException(status_code=413, detail="Audio file is too large.")
                temp_file.write(chunk)
    except Exception:
        os.unlink(temp_file.name)
        raise

    if size == 0:
        os.unlink(temp_file.name)
        raise HTTPException(status_code=400, detail="Uploaded audio file is empty.")

    return temp_file.name


def api_help() -> dict[str, object]:
    return {
        "service": "Local Speech Service",
        "description": "Convert text to speech locally and transcribe audio locally.",
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
                "save": False,
            },
            "example_request": {
                "text": "Hola, esto es una prueba local.",
                "lang_code": "e",
                "voice": "ef_dora",
                "speed": 1.0,
            },
            "direct_audio_response": {
                "request": {
                    "text": "Hola, esto devuelve audio/wav directamente.",
                    "lang_code": "e",
                    "voice": "ef_dora",
                },
                "response": "audio/wav bytes",
                "client_hint": "Use this mode when the HTTP client can store the binary response body as a .wav file.",
            },
            "downloadable_audio_response": {
                "request": {
                    "text": "Hola, esto devuelve una URL descargable.",
                    "lang_code": "e",
                    "voice": "ef_dora",
                    "save": True,
                },
                "response": {
                    "filename": "speech-<id>.wav",
                    "download_url": "/audio/speech-<id>.wav",
                    "content_type": "audio/wav",
                },
                "client_hint": "If calling from another machine, resolve download_url against this server origin, for example http://192.168.10.205:8000/audio/speech-<id>.wav.",
            },
        },
        "openai_compatible": {
            "speech": {
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
            "transcription": {
                "endpoint": "POST /v1/audio/transcriptions",
                "content_type": "multipart/form-data",
                "required_fields": ["file"],
                "optional_fields": {
                    "model": "whisper",
                    "language": "es",
                    "response_format": "json",
                },
            },
        },
        "limits": {
            "max_text_length": 10_000,
            "max_transcription_bytes": MAX_TRANSCRIPTION_BYTES,
            "speed_min": 0.5,
            "speed_max": 2.0,
            "sample_rate": SAMPLE_RATE,
            "audio_format": "wav",
            "generated_audio_dir": str(GENERATED_AUDIO_DIR),
            "transcription_model": DEFAULT_WHISPER_MODEL,
        },
        "metadata_endpoints": {
            "health": "GET /health",
            "voices": "GET /voices",
            "generated_audio": "GET /audio/{filename}",
            "transcribe": "GET /transcribe",
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
    #download { display: none; margin-top: 10px; color: #116466; font-weight: 700; }
    .panel { margin-top: 34px; padding-top: 24px; border-top: 1px solid #d3ccc0; }
    pre { white-space: pre-wrap; border: 1px solid #b8b2a7; border-radius: 8px; padding: 12px; background: #fffefa; min-height: 90px; }
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
    <a id="download" download="speech.wav">Descargar WAV</a>
    <section class="panel">
      <h2>Transcripcion</h2>
      <label>Audio
        <input id="audioFile" type="file" accept="audio/*,video/*">
      </label>
      <label>Idioma
        <input id="transcribeLang" value="es">
      </label>
      <button id="transcribe">Transcribir</button>
      <pre id="transcription"></pre>
    </section>
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
          body: JSON.stringify({ text: text.value, lang_code: lang.value, voice: voice.value, speed: Number(speed.value), save: true })
        });
        if (!response.ok) throw new Error(await response.text());
        const data = await response.json();
        audio.src = data.download_url;
        download.href = data.download_url;
        download.download = data.filename;
        download.style.display = "inline-block";
        await audio.play();
      } catch (error) {
        alert(error.message);
      } finally {
        speak.disabled = false;
      }
    });
    transcribe.addEventListener("click", async () => {
      if (!audioFile.files.length) return;
      transcribe.disabled = true;
      try {
        const body = new FormData();
        body.append("file", audioFile.files[0]);
        if (transcribeLang.value.trim()) body.append("language", transcribeLang.value.trim());
        const response = await fetch("/transcribe", { method: "POST", body });
        if (!response.ok) throw new Error(await response.text());
        const data = await response.json();
        transcription.textContent = data.text;
      } catch (error) {
        alert(error.message);
      } finally {
        transcribe.disabled = false;
      }
    });
  </script>
</body>
</html>
    """


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "ok": True,
        "sample_rate": SAMPLE_RATE,
        "loaded_languages": sorted(_pipelines),
        "transcription_model": DEFAULT_WHISPER_MODEL,
        "transcription_loaded": _whisper_model is not None,
    }


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
    if request.save:
        filename = await run_in_threadpool(save_generated_audio, audio)
        return JSONResponse(
            {
                "filename": filename,
                "download_url": f"/audio/{filename}",
                "content_type": "audio/wav",
            }
        )

    return wav_response(audio)


@app.get("/audio/{filename}")
def download_audio(filename: str) -> FileResponse:
    if not DOWNLOAD_FILENAME_PATTERN.fullmatch(filename):
        raise HTTPException(status_code=404, detail="Audio file not found.")

    path = GENERATED_AUDIO_DIR / filename
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Audio file not found.")

    return FileResponse(
        path,
        media_type="audio/wav",
        filename=filename,
    )


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


@app.get("/transcribe")
def transcribe_help() -> JSONResponse:
    return help_response()


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str | None = Form(default=None),
    task: Literal["transcribe", "translate"] = Form(default="transcribe"),
    response_format: Literal["json", "text"] = Form(default="json"),
) -> Response:
    temp_path = await save_upload_to_temp(file)
    try:
        result = await run_in_threadpool(transcribe_file, temp_path, language, task)
    finally:
        os.unlink(temp_path)

    if response_format == "text":
        return PlainTextResponse(str(result["text"]))

    return JSONResponse(result)


@app.get("/v1/audio/transcriptions")
def openai_transcriptions_help() -> JSONResponse:
    return help_response()


@app.post("/v1/audio/transcriptions")
async def openai_transcriptions(
    file: UploadFile = File(...),
    model: str = Form(default="whisper"),
    language: str | None = Form(default=None),
    response_format: Literal["json", "text"] = Form(default="json"),
) -> Response:
    if model not in {"whisper", "faster-whisper", DEFAULT_WHISPER_MODEL}:
        raise HTTPException(status_code=400, detail="Only the local Whisper model is supported.")

    temp_path = await save_upload_to_temp(file)
    try:
        result = await run_in_threadpool(transcribe_file, temp_path, language, "transcribe")
    finally:
        os.unlink(temp_path)

    if response_format == "text":
        return PlainTextResponse(str(result["text"]))

    return JSONResponse({"text": result["text"]})
