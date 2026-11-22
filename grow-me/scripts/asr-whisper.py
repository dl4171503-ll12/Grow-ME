# asr-whisper.py - local offline Chinese ASR with faster-whisper (CPU, no API)
# usage: py -3 asr-whisper.py <wav> [model_dir]
import sys
import time
import numpy as np
import soundfile as sf
from faster_whisper import WhisperModel

wav_path = sys.argv[1]
model_dir = sys.argv[2] if len(sys.argv) > 2 else r"C:\Users\David\.grow-me\asr\faster-whisper-base"

t0 = time.time()
model = WhisperModel(model_dir, device="cpu", compute_type="int8", cpu_threads=4)
data, rate = sf.read(wav_path, dtype="float32")
if getattr(data, "ndim", 1) > 1:
    data = data.mean(axis=1)
if rate != 16000:
    n = int(len(data) * 16000 / rate)
    idx = np.linspace(0, len(data) - 1, n)
    data = np.interp(idx, np.arange(len(data)), data).astype(np.float32)

segments, info = model.transcribe(
    data,
    language="zh",
    beam_size=1,
    best_of=1,
    vad_filter=True,
    condition_on_previous_text=False,
    temperature=0.0,
)
text = "".join(s.text for s in segments).strip()
print("ASR_TEXT " + text)
print("ASR_TIME %.2fs (audio %.1fs)" % (time.time() - t0, len(data) / 16000.0))
