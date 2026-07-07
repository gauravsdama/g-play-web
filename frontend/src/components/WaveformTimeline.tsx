import { useEffect, useMemo, useRef, useState } from "react";

export type CutRange = { start: number; end: number };

type WaveformTimelineProps = {
  audioUrl: string | null;
  height?: number;
  editable?: boolean;
  cuts?: CutRange[];
  onCutsChange?: (cuts: CutRange[]) => void;
  currentTime?: number;
  onSeek?: (time: number) => void;
};

const WaveformTimeline = ({
  audioUrl,
  height = 80,
  editable = false,
  cuts = [],
  onCutsChange,
  currentTime,
  onSeek,
}: WaveformTimelineProps) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [peaks, setPeaks] = useState<number[]>([]);
  const [duration, setDuration] = useState(0);
  const [zoom, setZoom] = useState(1);
  const [containerWidth, setContainerWidth] = useState(0);
  const [selection, setSelection] = useState<CutRange | null>(null);
  const [resizeState, setResizeState] = useState<{
    index: number;
    edge: "start" | "end";
  } | null>(null);
  const [autoScrollEnabled, setAutoScrollEnabled] = useState(true);
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number } | null>(null);
  const [userZoomed, setUserZoomed] = useState(false);
  const recoveryEligibleRef = useRef(false);
  const recoveryUsedRef = useRef(false);
  const autoRecoverActiveRef = useRef(false);
  const ignoreScrollRef = useRef(false);
  const autoScrollRef = useRef(true);
  const playheadRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const lastUpdatePerfRef = useRef(0);
  const lastTimeRef = useRef(0);
  const playbackRateRef = useRef(1);
  const targetTimeRef = useRef(0);

  useEffect(() => {
    if (!containerRef.current) {
      return;
    }
    const resizeObserver = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) {
        setContainerWidth(entry.contentRect.width);
      }
    });
    resizeObserver.observe(containerRef.current);
    return () => resizeObserver.disconnect();
  }, []);

  useEffect(() => {
    if (!audioUrl) {
      setPeaks([]);
      setDuration(0);
      return;
    }
    setUserZoomed(false);
    setAutoScrollEnabled(true);
    recoveryEligibleRef.current = false;
    recoveryUsedRef.current = false;
    autoRecoverActiveRef.current = false;
    let isActive = true;
    const audioContext = new AudioContext();
    fetch(audioUrl)
      .then((res) => res.arrayBuffer())
      .then((buffer) => audioContext.decodeAudioData(buffer))
      .then((decoded) => {
        if (!isActive) {
          return;
        }
        const channel = decoded.getChannelData(0);
        const points = Math.max(800, Math.floor(decoded.duration * 60));
        const blockSize = Math.max(1, Math.floor(channel.length / points));
        const nextPeaks: number[] = [];
        for (let i = 0; i < points; i += 1) {
          let max = 0;
          const start = i * blockSize;
          const end = Math.min(channel.length, start + blockSize);
          for (let j = start; j < end; j += 1) {
            const value = Math.abs(channel[j]);
            if (value > max) {
              max = value;
            }
          }
          nextPeaks.push(max);
        }
        setPeaks(nextPeaks);
        setDuration(decoded.duration || 0);
      })
      .catch(() => {
        if (isActive) {
          setPeaks([]);
          setDuration(0);
        }
      });
    return () => {
      isActive = false;
      audioContext.close().catch(() => undefined);
    };
  }, [audioUrl]);

  const canvasWidth = useMemo(() => Math.max(1, containerWidth * zoom), [containerWidth, zoom]);
  const maxZoom = useMemo(() => Math.max(6, Math.ceil(duration / 30) + 6), [duration]);

  useEffect(() => {
    if (duration <= 0 || userZoomed) {
      return;
    }
    const targetZoom = Math.max(1, duration / 30);
    setZoom(Number(targetZoom.toFixed(2)));
  }, [duration, userZoomed]);

  useEffect(() => {
    autoScrollRef.current = autoScrollEnabled;
  }, [autoScrollEnabled]);

  useEffect(() => {
    if (typeof currentTime !== "number") {
      return;
    }
    const now = performance.now();
    const prevTime = lastTimeRef.current;
    const prevPerf = lastUpdatePerfRef.current;
    targetTimeRef.current = currentTime;
    if (prevPerf > 0) {
      const deltaTime = currentTime - prevTime;
      const deltaPerf = (now - prevPerf) / 1000;
      if (deltaPerf > 0 && deltaTime >= 0 && deltaTime < 4) {
        const rate = deltaTime / deltaPerf;
        playbackRateRef.current = Math.max(0.25, Math.min(4, rate));
      } else {
        playbackRateRef.current = 1;
      }
    }
    lastTimeRef.current = currentTime;
    lastUpdatePerfRef.current = now;
  }, [currentTime]);

  useEffect(() => {
    const tick = () => {
      animationRef.current = requestAnimationFrame(tick);
      if (!containerRef.current || duration <= 0 || typeof currentTime !== "number") {
        if (playheadRef.current) {
          playheadRef.current.style.opacity = "0";
        }
        return;
      }
      const now = performance.now();
      const elapsed = (now - lastUpdatePerfRef.current) / 1000;
      let estimated = lastTimeRef.current;
      if (elapsed > 0 && elapsed < 1.5) {
        estimated = lastTimeRef.current + elapsed * playbackRateRef.current;
      } else {
        estimated = targetTimeRef.current;
      }
      if (playheadRef.current) {
        playheadRef.current.style.left = `${toLeft(estimated)}px`;
        playheadRef.current.style.opacity = "1";
      }
      const container = containerRef.current;
      const playhead = toLeft(estimated);
      const maxScroll = Math.max(0, canvasWidth - containerWidth);
      if (maxScroll <= 0) {
        return;
      }
      const target = playhead - containerWidth * 0.33;
      if (autoScrollRef.current) {
        applyScroll(target, 0.18);
        return;
      }
      if (!autoRecoverActiveRef.current && recoveryEligibleRef.current && !recoveryUsedRef.current) {
        const ratio = (playhead - container.scrollLeft) / containerWidth;
        if (ratio >= 0.75) {
          autoRecoverActiveRef.current = true;
        }
      }
      if (autoRecoverActiveRef.current) {
        applyScroll(target, 0.08);
        const ratio = (playhead - container.scrollLeft) / containerWidth;
        if (ratio <= 0.38) {
          autoRecoverActiveRef.current = false;
          recoveryUsedRef.current = true;
        }
      }
    };
    animationRef.current = requestAnimationFrame(tick);
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [duration, canvasWidth, containerWidth, currentTime]);

  useEffect(() => {
    if (!canvasRef.current) {
      return;
    }
    const canvas = canvasRef.current;
    canvas.width = canvasWidth;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }
    ctx.clearRect(0, 0, canvasWidth, height);
    ctx.fillStyle = "rgba(102, 124, 255, 0.8)";
    const mid = height / 2;
    const step = canvasWidth / Math.max(1, peaks.length);
    peaks.forEach((peak, index) => {
      const x = index * step;
      const barHeight = Math.max(2, peak * height * 0.9);
      ctx.fillRect(x, mid - barHeight / 2, Math.max(1, step * 0.8), barHeight);
    });
  }, [canvasWidth, height, peaks]);

  const toTime = (clientX: number) => {
    if (!containerRef.current || duration <= 0) {
      return 0;
    }
    const rect = containerRef.current.getBoundingClientRect();
    const scrollLeft = containerRef.current.scrollLeft;
    const localX = Math.min(rect.width, Math.max(0, clientX - rect.left));
    const absoluteX = scrollLeft + localX;
    return (absoluteX / canvasWidth) * duration;
  };

  const toLeft = (time: number) => {
    if (duration <= 0) {
      return 0;
    }
    return (time / duration) * canvasWidth;
  };

  const handlePointerDown = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!editable) {
      if (onSeek && duration > 0) {
        onSeek(toTime(event.clientX));
      }
      return;
    }
    setSelection({ start: toTime(event.clientX), end: toTime(event.clientX) });
  };

  const handlePointerMove = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!editable || !selection) {
      return;
    }
    setSelection({ start: selection.start, end: toTime(event.clientX) });
  };

  const handlePointerUp = () => {
    if (!editable || !selection || !onCutsChange) {
      setSelection(null);
      return;
    }
    const start = Math.min(selection.start, selection.end);
    const end = Math.max(selection.start, selection.end);
    if (end - start >= 0.2) {
      const next = [...cuts, { start, end }];
      onCutsChange(next);
    }
    setSelection(null);
  };

  useEffect(() => {
    if (!resizeState || !editable || !onCutsChange) {
      return;
    }
    const handleMove = (event: MouseEvent) => {
      const nextCuts = [...cuts];
      const target = nextCuts[resizeState.index];
      if (!target) {
        return;
      }
      const time = toTime(event.clientX);
      if (resizeState.edge === "start") {
        const start = Math.min(time, target.end - 0.1);
        nextCuts[resizeState.index] = { start: Math.max(0, start), end: target.end };
      } else {
        const end = Math.max(time, target.start + 0.1);
        nextCuts[resizeState.index] = { start: target.start, end: Math.min(duration, end) };
      }
      onCutsChange(nextCuts);
    };
    const handleUp = () => setResizeState(null);
    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleUp);
    return () => {
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleUp);
    };
  }, [resizeState, cuts, editable, duration, onCutsChange]);

  const sortedCuts = useMemo(() => {
    return [...cuts].sort((a, b) => a.start - b.start);
  }, [cuts]);

  const applyScroll = (target: number, smoothFactor: number) => {
    if (!containerRef.current) {
      return;
    }
    const container = containerRef.current;
    const maxScroll = Math.max(0, canvasWidth - containerWidth);
    const next = Math.max(0, Math.min(maxScroll, target));
    const current = container.scrollLeft;
    const blended = current + (next - current) * smoothFactor;
    if (Math.abs(blended - current) < 0.5) {
      return;
    }
    ignoreScrollRef.current = true;
    container.scrollLeft = blended;
    requestAnimationFrame(() => {
      ignoreScrollRef.current = false;
    });
  };

  useEffect(() => {
    const handleClick = () => setContextMenu(null);
    window.addEventListener("click", handleClick);
    return () => window.removeEventListener("click", handleClick);
  }, []);

  return (
    <div className="waveform">
      <div className="waveform-toolbar">
        <label>Zoom</label>
        <input
          type="range"
          min={1}
          max={maxZoom}
          step={0.5}
          value={zoom}
          onChange={(event) => {
            setZoom(Number(event.target.value));
            setUserZoomed(true);
          }}
        />
        <span className="muted">{duration ? `${duration.toFixed(1)}s` : "No audio"}</span>
      </div>
      <div
        className="waveform-track"
        ref={containerRef}
        onMouseDown={handlePointerDown}
        onMouseMove={handlePointerMove}
        onMouseUp={handlePointerUp}
        onMouseLeave={handlePointerUp}
        onScroll={() => {
          if (ignoreScrollRef.current) {
            ignoreScrollRef.current = false;
            return;
          }
          if (autoScrollRef.current) {
            setAutoScrollEnabled(false);
            recoveryEligibleRef.current = true;
            recoveryUsedRef.current = false;
            autoRecoverActiveRef.current = false;
          } else if (recoveryUsedRef.current) {
            recoveryEligibleRef.current = false;
          }
        }}
        onContextMenu={(event) => {
          event.preventDefault();
          setContextMenu({ x: event.clientX, y: event.clientY });
        }}
      >
        <canvas ref={canvasRef} />
        {sortedCuts.map((cut, index) => {
          const left = toLeft(cut.start);
          const right = toLeft(cut.end);
          return (
            <div
              key={`${cut.start}-${cut.end}-${index}`}
              className="cut-overlay"
              style={{ left, width: Math.max(2, right - left) }}
            >
              {editable ? (
                <>
                  <span
                    className="cut-handle left"
                    onMouseDown={(event) => {
                      event.stopPropagation();
                      setResizeState({ index, edge: "start" });
                    }}
                  />
                  <span
                    className="cut-handle right"
                    onMouseDown={(event) => {
                      event.stopPropagation();
                      setResizeState({ index, edge: "end" });
                    }}
                  />
                </>
              ) : null}
            </div>
          );
        })}
        {selection ? (
          <div
            className="cut-overlay pending"
            style={{
              left: Math.min(toLeft(selection.start), toLeft(selection.end)),
              width: Math.abs(toLeft(selection.end) - toLeft(selection.start)),
            }}
          />
        ) : null}
        {typeof currentTime === "number" && duration > 0 ? (
          <div className="playhead" ref={playheadRef} />
        ) : null}
      </div>
      {contextMenu ? (
        <div className="context-menu" style={{ top: contextMenu.y, left: contextMenu.x }}>
          <button
            onClick={() => {
              setAutoScrollEnabled((prev) => {
                const next = !prev;
                if (next) {
                  recoveryEligibleRef.current = false;
                  recoveryUsedRef.current = false;
                  setAutoRecoverActive(false);
                }
                return next;
              });
              setContextMenu(null);
            }}
          >
            Auto-scroll: {autoScrollEnabled ? "On" : "Off"}
          </button>
        </div>
      ) : null}
      {editable && sortedCuts.length > 0 ? (
        <div className="cut-list">
          {sortedCuts.map((cut, index) => (
            <div key={`${cut.start}-${cut.end}-chip`} className="cut-chip">
              <span>
                {cut.start.toFixed(1)}s - {cut.end.toFixed(1)}s
              </span>
              <button
                onClick={() => {
                  const next = sortedCuts.filter((_, idx) => idx !== index);
                  onCutsChange?.(next);
                }}
              >
                Remove
              </button>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
};

export default WaveformTimeline;
