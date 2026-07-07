import type { MutableRefObject } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { fetchAudioProfile } from "../api";
import { Track, VisualizerMode } from "../types";

export type VisualizerFrame = {
  frequency: Uint8Array;
  timeDomain?: Uint8Array;
  sampleRate: number;
  fftSize: number;
};

export type VisualizerSyncState = {
  barCount?: number;
  smoothing?: number;
  barColor?: string;
  glow?: boolean;
  autoScale?: boolean;
  manualMaxHz?: number;
  detectedMaxHz?: number | null;
};

type VisualizerViewProps = {
  track: Track | null;
  isPlaying: boolean;
  ensureAnalyser: () => Promise<AnalyserNode | null>;
  mode: VisualizerMode;
  genre: string;
  visualizerAuto: boolean;
  onVisualizerAutoChange: (value: boolean) => void;
  onGenreChange: (genre: string) => void;
  onModeChange: (mode: VisualizerMode) => void;
  useArtworkColors: boolean;
  onUseArtworkColorsChange: (value: boolean) => void;
  standalone?: boolean;
  onOpenStandalone?: () => void;
  broadcastChannel?: string;
  externalFrameRef?: MutableRefObject<VisualizerFrame | null>;
  syncState?: VisualizerSyncState | null;
};

const GENRE_OPTIONS = [
  "Electronic",
  "Chill",
  "Sleepy",
  "Wakeful",
  "Beach/Tropical",
  "Hip-Hop",
  "Rock",
  "Pop",
  "Jazz",
  "Classical",
  "RnB",
  "Acoustic",
  "Psychedelic",
  "Other",
];

const MODE_OPTIONS: VisualizerMode[] = [
  "Trippy/Psychedelic",
  "Chill",
  "Sleepy",
  "Wakeful",
  "Electronic",
  "Beachy/Tropical",
];

const VisualizerView = ({
  track,
  isPlaying,
  ensureAnalyser,
  mode,
  genre,
  visualizerAuto,
  onVisualizerAutoChange,
  onGenreChange,
  onModeChange,
  useArtworkColors,
  onUseArtworkColorsChange,
  standalone = false,
  onOpenStandalone,
  broadcastChannel,
  externalFrameRef,
  syncState,
}: VisualizerViewProps) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const [started, setStarted] = useState(standalone);
  const [barCount, setBarCount] = useState(64);
  const [smoothing, setSmoothing] = useState(0.6);
  const [barColor, setBarColor] = useState("#6f7cff");
  const [glow, setGlow] = useState(true);
  const [palette, setPalette] = useState<string[] | null>(null);
  const [autoScale, setAutoScale] = useState(true);
  const [manualMaxHz, setManualMaxHz] = useState(16000);
  const [detectedMaxHz, setDetectedMaxHz] = useState<number | null>(null);
  const [analysisStatus, setAnalysisStatus] = useState<string | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const channelRef = useRef<BroadcastChannel | null>(null);
  const lastFrameSentRef = useRef(0);
  const trippyRef = useRef<{
    orbs: {
      angle: number;
      radius: number;
      speed: number;
      size: number;
      hue: number;
      phase: number;
      drift: number;
      beat: number;
    }[];
  } | null>(null);

  useEffect(() => {
    if (standalone) {
      setStarted(true);
    }
  }, [standalone]);

  useEffect(() => {
    if (fullscreen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => {
      document.body.style.overflow = "";
    };
  }, [fullscreen]);

  const activeColors = useMemo(() => {
    if (useArtworkColors && palette && palette.length > 0) {
      return {
        primary: palette[0],
        secondary: palette[1] || "#2e9bff",
      };
    }
    return { primary: barColor, secondary: "#2e9bff" };
  }, [useArtworkColors, palette, barColor]);

  const maxFrequencyHz = autoScale && detectedMaxHz ? detectedMaxHz : manualMaxHz;

  useEffect(() => {
    if (!syncState) {
      return;
    }
    if (typeof syncState.barCount === "number") {
      setBarCount(syncState.barCount);
    }
    if (typeof syncState.smoothing === "number") {
      setSmoothing(syncState.smoothing);
    }
    if (typeof syncState.barColor === "string") {
      setBarColor(syncState.barColor);
    }
    if (typeof syncState.glow === "boolean") {
      setGlow(syncState.glow);
    }
    if (typeof syncState.autoScale === "boolean") {
      setAutoScale(syncState.autoScale);
    }
    if (typeof syncState.manualMaxHz === "number") {
      setManualMaxHz(syncState.manualMaxHz);
    }
    if (syncState.detectedMaxHz !== undefined) {
      setDetectedMaxHz(syncState.detectedMaxHz);
    }
  }, [syncState]);

  useEffect(() => {
    if (!useArtworkColors || !track?.thumbnail) {
      setPalette(null);
      return;
    }
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.src = track.thumbnail;
    img.onload = () => {
      const sampleCanvas = document.createElement("canvas");
      const size = 32;
      sampleCanvas.width = size;
      sampleCanvas.height = size;
      const ctx = sampleCanvas.getContext("2d");
      if (!ctx) {
        return;
      }
      ctx.drawImage(img, 0, 0, size, size);
      const data = ctx.getImageData(0, 0, size, size).data;
      let rTotal = 0;
      let gTotal = 0;
      let bTotal = 0;
      let count = 0;
      let bestSat = 0;
      let bestColor = [111, 124, 255];
      for (let i = 0; i < data.length; i += 4) {
        const alpha = data[i + 3];
        if (alpha < 50) {
          continue;
        }
        const r = data[i];
        const g = data[i + 1];
        const b = data[i + 2];
        rTotal += r;
        gTotal += g;
        bTotal += b;
        count += 1;
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        const sat = max === 0 ? 0 : (max - min) / max;
        if (sat > bestSat) {
          bestSat = sat;
          bestColor = [r, g, b];
        }
      }
      if (!count) {
        return;
      }
      const avg = [Math.round(rTotal / count), Math.round(gTotal / count), Math.round(bTotal / count)];
      const toHex = (value: number) => value.toString(16).padStart(2, "0");
      const colorHex = (color: number[]) => `#${toHex(color[0])}${toHex(color[1])}${toHex(color[2])}`;
      setPalette([colorHex(bestColor), colorHex(avg)]);
    };
    img.onerror = () => setPalette(null);
  }, [track?.thumbnail, useArtworkColors]);

  useEffect(() => {
    if (!track || !autoScale || standalone) {
      return;
    }
    let isActive = true;
    setAnalysisStatus("Analyzing track...");
    fetchAudioProfile(track.root, track.path)
      .then((data) => {
        if (!isActive) {
          return;
        }
        setDetectedMaxHz(Math.max(2000, Math.min(20000, data.max_frequency_hz || 20000)));
        setAnalysisStatus(null);
      })
      .catch((error) => {
        if (!isActive) {
          return;
        }
        setAnalysisStatus((error as Error).message);
      });
    return () => {
      isActive = false;
    };
  }, [track, autoScale]);

  const sendState = useCallback(() => {
    if (!channelRef.current) {
      return;
    }
    channelRef.current.postMessage({
      type: "state",
      track,
      isPlaying,
      mode,
      genre,
      visualizerAuto,
      useArtworkColors,
      barCount,
      smoothing,
      barColor,
      glow,
      autoScale,
      manualMaxHz,
      detectedMaxHz,
    });
  }, [
    track,
    isPlaying,
    mode,
    genre,
    visualizerAuto,
    useArtworkColors,
    barCount,
    smoothing,
    barColor,
    glow,
    autoScale,
    manualMaxHz,
    detectedMaxHz,
  ]);

  useEffect(() => {
    if (!broadcastChannel || standalone) {
      return;
    }
    const channel = new BroadcastChannel(broadcastChannel);
    channelRef.current = channel;
    channel.onmessage = (event) => {
      if (event.data?.type === "request_state") {
        sendState();
      }
    };
    sendState();
    return () => {
      channel.close();
      channelRef.current = null;
    };
  }, [broadcastChannel, sendState, standalone]);

  useEffect(() => {
    if (broadcastChannel && !standalone) {
      sendState();
    }
  }, [sendState, broadcastChannel, standalone]);

  useEffect(() => {
    if (!started) {
      return;
    }
    let analyser: AnalyserNode | null = null;
    let dataArray: Uint8Array | null = null;
    let timeArray: Uint8Array | null = null;
    let sampleRate = 44100;
    let fftSize = 2048;

    const draw = () => {
      const externalFrame = externalFrameRef?.current || null;
      if (!canvasRef.current || (!externalFrame && (!analyser || !dataArray))) {
        animationRef.current = requestAnimationFrame(draw);
        return;
      }
      const canvas = canvasRef.current;
      const ctx = canvas.getContext("2d");
      if (!ctx) {
        animationRef.current = requestAnimationFrame(draw);
        return;
      }
      const { width, height } = canvas;
      ctx.clearRect(0, 0, width, height);
      let frameData = dataArray;
      let frameTime = timeArray;
      if (externalFrame) {
        frameData = externalFrame.frequency;
        frameTime = externalFrame.timeDomain || null;
        sampleRate = externalFrame.sampleRate;
        fftSize = externalFrame.fftSize;
      } else if (analyser && dataArray) {
        analyser.smoothingTimeConstant = smoothing;
        analyser.getByteFrequencyData(dataArray);
        if (channelRef.current) {
          if (!timeArray) {
            timeArray = new Uint8Array(analyser.fftSize);
          }
          analyser.getByteTimeDomainData(timeArray);
          frameTime = timeArray;
        }
        sampleRate = analyser.context.sampleRate;
        fftSize = analyser.fftSize;
      }

      if (!frameData) {
        animationRef.current = requestAnimationFrame(draw);
        return;
      }

      const binHz = sampleRate / fftSize;
      const maxBin = Math.max(
        1,
        Math.min(frameData.length - 1, Math.floor(maxFrequencyHz / binHz))
      );
      const step = Math.max(1, Math.floor(maxBin / barCount));
      const barWidth = width / barCount;

      const primary = activeColors.primary;
      const secondary = activeColors.secondary;

      if (mode === "Trippy/Psychedelic") {
        const time = performance.now() / 1000;
        const energyBins = Math.min(48, maxBin);
        let bass = 0;
        let total = 0;
        for (let i = 0; i < energyBins; i += 1) {
          const value = frameData[i] || 0;
          total += value;
          if (i < 16) {
            bass += value;
          }
        }
        const pulse = energyBins ? bass / (16 * 255) : 0;
        const avg = energyBins ? total / (energyBins * 255) : 0;
        if (!trippyRef.current) {
          trippyRef.current = {
            orbs: Array.from({ length: 18 }, (_, idx) => ({
              angle: Math.random() * Math.PI * 2,
              radius: (Math.min(width, height) / 4) * (0.5 + Math.random()),
              speed: 0.2 + Math.random() * 0.6,
              size: 24 + Math.random() * 48,
              hue: (idx * 20 + Math.random() * 30) % 360,
              phase: Math.random() * Math.PI * 2,
              drift: 0.3 + Math.random() * 0.7,
              beat: 0.4 + Math.random() * 0.8,
            })),
          };
        }
        const centerX = width / 2;
        const centerY = height / 2;
        ctx.globalCompositeOperation = "source-over";
        ctx.fillStyle = `rgba(6, 8, 16, ${0.12 + avg * 0.18})`;
        ctx.fillRect(0, 0, width, height);
        ctx.globalCompositeOperation = "lighter";
        const ringCount = 4;
        for (let ring = 0; ring < ringCount; ring += 1) {
          ctx.beginPath();
          const ringHue = (time * 30 + ring * 90) % 360;
          ctx.strokeStyle = `hsla(${ringHue}, 80%, 60%, 0.35)`;
          ctx.lineWidth = 1.5;
          for (let i = 0; i <= 80; i += 1) {
            const angle = (i / 80) * Math.PI * 2;
            const wave =
              Math.sin(angle * 3 + time * 1.3 + ring) * (24 + pulse * 40) +
              Math.cos(angle * 2 + time * 0.8) * (12 + avg * 22);
            const radius = Math.min(width, height) * (0.18 + ring * 0.06) + wave;
            const x = centerX + Math.cos(angle) * radius;
            const y = centerY + Math.sin(angle) * radius;
            if (i === 0) {
              ctx.moveTo(x, y);
            } else {
              ctx.lineTo(x, y);
            }
          }
          ctx.stroke();
        }
        trippyRef.current.orbs.forEach((orb, index) => {
          orb.angle += orb.speed * (0.4 + pulse * orb.beat);
          const wobble = Math.sin(time * orb.drift + orb.phase) * (18 + avg * 60);
          const radius = orb.radius + wobble;
          const x = centerX + Math.cos(orb.angle + time * 0.2) * radius;
          const y = centerY + Math.sin(orb.angle + time * 0.15) * radius;
          const size = orb.size * (0.6 + orb.beat * pulse + avg * 1.2);
          const hue = (orb.hue + time * 40 + index * 4) % 360;
          const grad = ctx.createRadialGradient(x, y, 0, x, y, size);
          grad.addColorStop(0, `hsla(${hue}, 90%, 70%, 0.85)`);
          grad.addColorStop(1, `hsla(${hue}, 90%, 60%, 0)`);
          ctx.fillStyle = grad;
          ctx.beginPath();
          ctx.arc(x, y, size, 0, Math.PI * 2);
          ctx.fill();
        });
        ctx.globalCompositeOperation = "source-over";
      } else if (mode === "Sleepy") {
        if (!frameTime && analyser) {
          if (!timeArray) {
            timeArray = new Uint8Array(analyser.fftSize);
          }
          analyser.getByteTimeDomainData(timeArray);
          frameTime = timeArray;
        }
        if (!frameTime) {
          animationRef.current = requestAnimationFrame(draw);
          return;
        }
        ctx.strokeStyle = primary;
        ctx.lineWidth = 2;
        ctx.shadowColor = primary;
        ctx.shadowBlur = glow ? 30 : 0;
        ctx.beginPath();
        const sliceWidth = width / frameTime.length;
        let x = 0;
        for (let i = 0; i < frameTime.length; i += 1) {
          const v = frameTime[i] / 128.0;
          const y = (v * height) / 2;
          if (i === 0) {
            ctx.moveTo(x, y);
          } else {
            ctx.lineTo(x, y);
          }
          x += sliceWidth;
        }
        ctx.lineTo(width, height / 2);
        ctx.stroke();
      } else if (mode === "Beachy/Tropical") {
        const waveCount = 3;
        for (let wave = 0; wave < waveCount; wave += 1) {
          ctx.beginPath();
          ctx.strokeStyle = wave % 2 === 0 ? primary : secondary;
          ctx.lineWidth = 2;
          ctx.shadowColor = secondary;
          ctx.shadowBlur = glow ? 16 : 0;
          for (let i = 0; i < barCount; i += 1) {
            const slice = frameData.slice(i * step, Math.min(i * step + step, maxBin));
            const avg = slice.reduce((acc, val) => acc + val, 0) / slice.length;
            const normalized = avg / 255;
            const x = i * barWidth;
            const y =
              height * (0.35 + wave * 0.15) -
              Math.sin((i / barCount) * Math.PI * 2 + wave) * 30 * normalized;
            if (i === 0) {
              ctx.moveTo(x, y);
            } else {
              ctx.lineTo(x, y);
            }
          }
          ctx.stroke();
        }
      } else if (mode === "Electronic") {
        for (let i = 0; i < barCount; i += 1) {
          const slice = frameData.slice(i * step, Math.min(i * step + step, maxBin));
          const avg = slice.reduce((acc, val) => acc + val, 0) / slice.length;
          const normalized = avg / 255;
          const barHeight = Math.max(8, normalized * height * 0.9);
          const x = i * barWidth;
          const y = height / 2 - barHeight / 2;
          ctx.fillStyle = i % 2 === 0 ? primary : secondary;
          ctx.shadowColor = primary;
          ctx.shadowBlur = glow ? 20 : 0;
          ctx.fillRect(x + barWidth * 0.15, y, barWidth * 0.7, barHeight);
        }
      } else {
        for (let i = 0; i < barCount; i += 1) {
          const slice = frameData.slice(i * step, Math.min(i * step + step, maxBin));
          const avg = slice.reduce((acc, val) => acc + val, 0) / slice.length;
          const normalized = avg / 255;
          const scale = mode === "Wakeful" ? 1.05 : 0.85;
          const barHeight = Math.max(6, normalized * height * scale);
          const x = i * barWidth;
          const y = height - barHeight;
          if (glow) {
            ctx.shadowColor = primary;
            ctx.shadowBlur = mode === "Wakeful" ? 24 : 18;
          } else {
            ctx.shadowBlur = 0;
          }
          ctx.fillStyle = primary;
          ctx.fillRect(x + barWidth * 0.12, y, barWidth * 0.76, barHeight);
        }
      }

      if (channelRef.current && !standalone && analyser) {
        const now = performance.now();
        if (now - lastFrameSentRef.current > 33) {
          lastFrameSentRef.current = now;
          channelRef.current.postMessage({
            type: "frame",
            frame: {
              frequency: new Uint8Array(dataArray || []),
              timeDomain: timeArray ? new Uint8Array(timeArray) : undefined,
              sampleRate: analyser.context.sampleRate,
              fftSize: analyser.fftSize,
            },
          });
        }
      }
      animationRef.current = requestAnimationFrame(draw);
    };

    if (externalFrameRef) {
      animationRef.current = requestAnimationFrame(draw);
    } else {
      ensureAnalyser().then((node) => {
        if (!node) {
          return;
        }
        analyser = node;
        analyser.fftSize = 2048;
        dataArray = new Uint8Array(analyser.frequencyBinCount);
        animationRef.current = requestAnimationFrame(draw);
      });
    }

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [
    started,
    barCount,
    smoothing,
    barColor,
    glow,
    mode,
    activeColors,
    maxFrequencyHz,
    externalFrameRef,
    standalone,
  ]);

  const title = track?.title || track?.path?.split("/").pop() || "No track";

  return (
    <div className={`view visualizer-view ${standalone ? "standalone" : ""} ${fullscreen ? "fullscreen" : ""}`}>
      {!standalone ? (
        <div className="visualizer-top">
        <div>
          <h2>Visualizer</h2>
          <p className="muted">
            {track
              ? `Now visualizing: ${title}`
              : "Select a downloaded track from the Explorer and press play."}
          </p>
        </div>
        <button
          className={`btn primary huge ${started ? "active" : ""}`}
          onClick={() => setStarted(true)}
        >
          {started ? "Visualizer Running" : "Start Visualization"}
        </button>
      </div>
      ) : null}
      {!standalone ? (
        <div className="visualizer-controls">
        <div className="field">
          <label>Genre</label>
          <select value={genre} onChange={(event) => onGenreChange(event.target.value)}>
            {GENRE_OPTIONS.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </div>
        <div className="field checkbox">
          <label>Auto mode from genre</label>
          <input
            type="checkbox"
            checked={visualizerAuto}
            onChange={(event) => onVisualizerAutoChange(event.target.checked)}
          />
        </div>
        <div className="field">
          <label>Visualizer mode</label>
          <select
            value={mode}
            onChange={(event) => onModeChange(event.target.value as VisualizerMode)}
            disabled={visualizerAuto}
          >
            {MODE_OPTIONS.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </div>
        <div className="field checkbox">
          <label>Use artwork colors</label>
          <input
            type="checkbox"
            checked={useArtworkColors}
            onChange={(event) => onUseArtworkColorsChange(event.target.checked)}
          />
        </div>
        <div className="field checkbox">
          <label>Auto scale from track</label>
          <input
            type="checkbox"
            checked={autoScale}
            onChange={(event) => setAutoScale(event.target.checked)}
          />
        </div>
        <div className="field">
          <label>Max frequency</label>
          <input
            type="range"
            min={4000}
            max={20000}
            step={500}
            value={manualMaxHz}
            disabled={autoScale}
            onChange={(event) => setManualMaxHz(Number(event.target.value))}
          />
          <span className="muted">
            Scale: 0 - {Math.round(maxFrequencyHz)} Hz
          </span>
          {analysisStatus ? <span className="muted">{analysisStatus}</span> : null}
        </div>
      </div>
      ) : null}
      <div className="visualizer-canvas">
        <canvas ref={canvasRef} width={1200} height={520} />
        {!isPlaying ? <div className="visualizer-overlay">Play audio to animate.</div> : null}
        <button
          className="visualizer-fullscreen-toggle"
          onClick={() => setFullscreen((prev) => !prev)}
        >
          {fullscreen ? "Reduce" : "Full Screen"}
        </button>
      </div>
      {!standalone ? (
        <div className="visualizer-controls">
        <div className="field">
          <label>Bars</label>
          <input
            type="range"
            min={24}
            max={128}
            step={4}
            value={barCount}
            onChange={(event) => setBarCount(Number(event.target.value))}
          />
        </div>
        <div className="field">
          <label>Smoothing</label>
          <input
            type="range"
            min={0}
            max={0.9}
            step={0.05}
            value={smoothing}
            onChange={(event) => setSmoothing(Number(event.target.value))}
          />
        </div>
        <div className="field">
          <label>Bar Color</label>
          <input type="color" value={barColor} onChange={(event) => setBarColor(event.target.value)} />
        </div>
        <div className="field checkbox">
          <label>Glow</label>
          <input
            type="checkbox"
            checked={glow}
            onChange={(event) => setGlow(event.target.checked)}
          />
        </div>
      </div>
      ) : null}
    </div>
  );
};

export default VisualizerView;
