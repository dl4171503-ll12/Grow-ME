# voice-loudness.py - loudness maximizer for speech (compressor + makeup + limiter)
# usage: py -3 voice-loudness.py in.wav [out.wav]
import sys
import numpy as np
import soundfile as sf

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else src
mode = sys.argv[3] if len(sys.argv) > 3 else "compress"

data, rate = sf.read(src, dtype="float32")
if getattr(data, "ndim", 1) > 1:
    data = data.mean(axis=1)
x = data.astype(np.float64).copy()
if x.size == 0:
    sys.exit(0)

x = x - np.mean(x)
eps = 1e-9

if mode == "peak":
    peak = float(np.max(np.abs(x))) + eps
    y = x * (0.92 / peak) if peak > 0 else x
    sf.write(dst, y.astype(np.float32), rate, subtype="PCM_16")
    rms_before = float(np.sqrt(np.mean(x * x)))
    rms_after = float(np.sqrt(np.mean(y * y)))
    print("PEAK rms_before=%.5f rms_after=%.5f" % (rms_before, rms_after))
    sys.exit(0)

# RMS envelope (15 ms window)
win = max(1, int(0.015 * rate))
env = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))

# upward compression: lift quiet parts toward target, harder for "max volume"
target = 0.32
gain = (target / (env + eps)) ** 0.92
gain = np.clip(gain, 1.0, 40.0)

# smooth the gain curve (20 ms)
wg = max(1, int(0.02 * rate))
gain = np.convolve(gain, np.ones(wg) / wg, mode="same")

y = x * gain

# soft limiter (tanh saturation) then peak normalise close to full scale
y = np.tanh(y * 1.25) / np.tanh(1.25)
peak = float(np.max(np.abs(y))) + eps
if peak > 0:
    y = y * (0.98 / peak)

sf.write(dst, y.astype(np.float32), rate, subtype="PCM_16")
rms_before = float(np.sqrt(np.mean(x * x)))
rms_after = float(np.sqrt(np.mean(y * y)))
print("LOUD rms_before=%.5f rms_after=%.5f rate=%d" % (rms_before, rms_after, rate))
