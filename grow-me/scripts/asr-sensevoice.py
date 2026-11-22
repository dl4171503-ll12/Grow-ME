# asr-sensevoice.py - local offline Chinese ASR with SenseVoice (sherpa-onnx, CPU, no API)
# usage: py -3 asr-sensevoice.py <wav> [model_dir]
import os
import sys
import time

import numpy as np
import sherpa_onnx
import soundfile as sf

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

wav_path = sys.argv[1]
model_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.expanduser("~"), ".grow-me", "asr", "sensevoice"
)
model = os.path.join(model_dir, "model.int8.onnx")
tokens = os.path.join(model_dir, "tokens.txt")
if not (os.path.exists(model) and os.path.exists(tokens)):
    print("ASR_ERROR model missing in " + model_dir)
    sys.exit(3)

t0 = time.time()
recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
    model=model,
    tokens=tokens,
    num_threads=4,
    use_itn=True,
    language="zh",
    debug=False,
)
samples, sample_rate = sf.read(wav_path, dtype="float32")
if getattr(samples, "ndim", 1) > 1:
    samples = samples.mean(axis=1)
if sample_rate != 16000:
    n = int(len(samples) * 16000 / sample_rate)
    idx = np.linspace(0, len(samples) - 1, n)
    samples = np.interp(idx, np.arange(len(samples)), samples).astype(np.float32)
    sample_rate = 16000
stream = recognizer.create_stream()
stream.accept_waveform(sample_rate, samples)
recognizer.decode_stream(stream)
text = stream.result.text.strip()
print("ASR_TEXT " + text)
print("ASR_TIME %.2fs (audio %.1fs)" % (time.time() - t0, len(samples) / float(sample_rate)))
