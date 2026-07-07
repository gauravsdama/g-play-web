import { useEffect, useRef, useState } from "react";

const formatTime = (seconds: number) => {
  if (!Number.isFinite(seconds)) {
    return "0:00";
  }
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
};

type AudioScrubberProps = {
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
};

const AudioScrubber = ({ currentTime, duration, onSeek }: AudioScrubberProps) => {
  const trackRef = useRef<HTMLDivElement | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const percent = duration > 0 ? Math.min(100, (currentTime / duration) * 100) : 0;

  const seekFromClientX = (clientX: number) => {
    if (!trackRef.current || duration <= 0) {
      return;
    }
    const rect = trackRef.current.getBoundingClientRect();
    const clamped = Math.min(rect.right, Math.max(rect.left, clientX));
    const ratio = (clamped - rect.left) / rect.width;
    onSeek(ratio * duration);
  };

  useEffect(() => {
    if (!isDragging) {
      return;
    }
    const handleMove = (event: MouseEvent) => {
      seekFromClientX(event.clientX);
    };
    const handleUp = () => {
      setIsDragging(false);
    };
    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleUp);
    return () => {
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleUp);
    };
  }, [isDragging, duration]);

  return (
    <div className="scrubber">
      <span className="scrubber-time">{formatTime(currentTime)}</span>
      <div
        className="scrubber-track"
        ref={trackRef}
        onMouseDown={(event) => {
          setIsDragging(true);
          seekFromClientX(event.clientX);
        }}
      >
        <div className="scrubber-fill" style={{ width: `${percent}%` }} />
        <div className="scrubber-thumb" style={{ left: `${percent}%` }} />
      </div>
      <span className="scrubber-time">{formatTime(duration)}</span>
    </div>
  );
};

export default AudioScrubber;
