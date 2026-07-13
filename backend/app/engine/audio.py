from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import List, Tuple

import numpy as np

from .config import PROCESSING_THREADS
from .schemas import CutRange


def ffmpeg_thread_args() -> List[str]:
    return ["-threads", str(PROCESSING_THREADS)]


def decode_audio_mono(path: Path, sample_rate: int) -> np.ndarray:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        *ffmpeg_thread_args(),
        "-i",
        str(path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-f",
        "f32le",
        "pipe:1",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
    data = np.frombuffer(proc.stdout, dtype=np.float32)
    return data


def read_duration_seconds(path: Path) -> float:
    if not shutil.which("ffprobe"):
        raise RuntimeError("ffprobe is required")
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "json",
        str(path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
    data = json.loads(proc.stdout.decode("utf-8", errors="replace"))
    duration = float(data.get("format", {}).get("duration") or 0)
    return max(0.0, duration)


def normalize_cuts(cuts: List[CutRange], duration: float) -> List[Tuple[float, float]]:
    normalized: List[Tuple[float, float]] = []
    for cut in cuts:
        start = max(0.0, min(duration, float(cut.start)))
        end = max(0.0, min(duration, float(cut.end)))
        if end <= start:
            continue
        normalized.append((start, end))
    normalized.sort(key=lambda item: item[0])
    merged: List[Tuple[float, float]] = []
    for start, end in normalized:
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def build_keep_segments(cuts: List[Tuple[float, float]], duration: float) -> List[Tuple[float, float]]:
    keep: List[Tuple[float, float]] = []
    cursor = 0.0
    for start, end in cuts:
        if start > cursor:
            keep.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < duration:
        keep.append((cursor, duration))
    return [(start, end) for start, end in keep if end > start]


def render_cut_audio(source: Path, dest: Path, segments: List[Tuple[float, float]]) -> None:
    filters: List[str] = []
    labels: List[str] = []
    for index, (start, end) in enumerate(segments):
        label = f"a{index}"
        filters.append(
            f"[0:a]atrim=start={start:.3f}:end={end:.3f},asetpts=PTS-STARTPTS[{label}]"
        )
        labels.append(f"[{label}]")
    concat = f"{''.join(labels)}concat=n={len(labels)}:v=0:a=1[out]"
    filter_chain = ";".join(filters + [concat])
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        *ffmpeg_thread_args(),
        "-y",
        "-i",
        str(source),
        "-filter_threads",
        str(PROCESSING_THREADS),
        "-filter_complex",
        filter_chain,
        "-map",
        "[out]",
        "-f",
        "mp3",
        "-ar",
        "48000",
        "-codec:a",
        "libmp3lame",
        "-b:a",
        "320k",
        *ffmpeg_thread_args(),
        str(dest),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))


def compute_max_frequency(
    path: Path,
    min_coverage: float = 0.02,
    sample_rate: int = 22050,
    window: int = 2048,
    hop: int = 1024,
) -> Tuple[float, int]:
    samples = decode_audio_mono(path, sample_rate)
    if samples.size < window:
        return float(sample_rate / 2), sample_rate

    window_fn = np.hanning(window).astype(np.float32)
    counts = np.zeros(window // 2 + 1, dtype=np.int32)
    frames = 0

    for index in range(0, samples.size - window + 1, hop):
        frame = samples[index : index + window] * window_fn
        spectrum = np.abs(np.fft.rfft(frame))
        max_mag = spectrum.max()
        if max_mag <= 0:
            continue
        threshold = max_mag * 0.05
        active = spectrum >= threshold
        counts[active] += 1
        frames += 1

    if frames == 0:
        return float(sample_rate / 2), sample_rate

    required = max(1, int(frames * min_coverage))
    valid_bins = np.where(counts >= required)[0]
    if valid_bins.size == 0:
        max_bin = int(window / 2)
    else:
        max_bin = int(valid_bins.max())
    max_freq = max_bin * sample_rate / window
    return float(max_freq), sample_rate


def build_filter_chain(
    preamp_db: float,
    eq_gains: List[float],
    spatial_width: float,
    drc_mode: str,
    balance: float,
    limiter_on: bool,
) -> str:
    filters: List[str] = []
    eq_bands = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    for freq, gain in zip(eq_bands, eq_gains or [0.0] * len(eq_bands)):
        if abs(gain) >= 0.1:
            filters.append(f"equalizer=f={freq}:t=q:w=1:g={gain:.2f}")

    if drc_mode != "Off":
        settings_by_mode = {
            "Soft": {"threshold": -16, "ratio": 1.8, "attack": 30, "release": 220, "makeup": 1.5},
            "Medium": {"threshold": -20, "ratio": 2.5, "attack": 20, "release": 250, "makeup": 3},
            "High": {"threshold": -28, "ratio": 4.0, "attack": 12, "release": 300, "makeup": 6},
        }
        settings = settings_by_mode.get(drc_mode)
        if not settings:
            raise ValueError(f"Unsupported DRC mode: {drc_mode}")
        filters.append(
            "acompressor="
            f"threshold={settings['threshold']}dB:"
            f"ratio={settings['ratio']}:"
            f"attack={settings['attack']}:"
            f"release={settings['release']}:"
            f"makeup={settings['makeup']}"
        )

    if spatial_width > 0:
        crossfeed = min(0.8, 0.1 + spatial_width * 0.7)
        feedback = min(0.9, 0.1 + spatial_width * 0.6)
        drymix = max(0.6, 1.0 - spatial_width * 0.3)
        filters.append(
            "stereowiden="
            f"delay=20:feedback={feedback:.2f}:crossfeed={crossfeed:.2f}:drymix={drymix:.2f}"
        )

    if abs(balance) > 0.01:
        if balance < 0:
            left = 1.0
            right = 1.0 + balance
        else:
            left = 1.0 - balance
            right = 1.0
        filters.append(f"pan=stereo|c0={left:.3f}*c0|c1={right:.3f}*c1")

    if abs(preamp_db) > 0.01:
        filters.append(f"volume={preamp_db:.2f}dB")

    if limiter_on:
        filters.append("alimiter=limit=0.95")

    return ",".join(filters) if filters else "anull"


def process_audio(input_path: Path, output_path: Path, filter_chain: str) -> None:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        *ffmpeg_thread_args(),
        "-y",
        "-i",
        str(input_path),
        "-filter_threads",
        str(PROCESSING_THREADS),
        "-af",
        filter_chain,
        "-f",
        "mp3",
        "-ar",
        "48000",
        "-codec:a",
        "libmp3lame",
        "-b:a",
        "320k",
        *ffmpeg_thread_args(),
        str(output_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
