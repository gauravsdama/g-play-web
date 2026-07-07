import { useEffect, useRef, useState } from "react";
import AudioScrubber from "./AudioScrubber";
import WaveformTimeline from "./WaveformTimeline";

const formatTime = (seconds: number) => {
  if (!Number.isFinite(seconds)) {
    return "0:00";
  }
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
};

type MiniPlayerProps = {
  label: string;
  src: string | null;
  showWaveform?: boolean;
};

const MiniPlayer = ({ label, src, showWaveform = true }: MiniPlayerProps) => {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) {
      return;
    }
    const handlePlay = () => setIsPlaying(true);
    const handlePause = () => setIsPlaying(false);
    const handleTime = () => setCurrentTime(audio.currentTime || 0);
    const handleMeta = () => setDuration(audio.duration || 0);
    audio.addEventListener("play", handlePlay);
    audio.addEventListener("pause", handlePause);
    audio.addEventListener("timeupdate", handleTime);
    audio.addEventListener("loadedmetadata", handleMeta);
    audio.addEventListener("ended", handlePause);
    return () => {
      audio.removeEventListener("play", handlePlay);
      audio.removeEventListener("pause", handlePause);
      audio.removeEventListener("timeupdate", handleTime);
      audio.removeEventListener("loadedmetadata", handleMeta);
      audio.removeEventListener("ended", handlePause);
    };
  }, []);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) {
      return;
    }
    audio.pause();
    audio.currentTime = 0;
    setCurrentTime(0);
    setDuration(0);
    setIsPlaying(false);
  }, [src]);

  const togglePlay = () => {
    const audio = audioRef.current;
    if (!audio || !src) {
      return;
    }
    if (audio.paused) {
      audio.play().catch(() => setIsPlaying(false));
    } else {
      audio.pause();
    }
  };

  const handleSeek = (time: number) => {
    const audio = audioRef.current;
    if (!audio) {
      return;
    }
    audio.currentTime = time;
    setCurrentTime(time);
  };

  return (
    <div className="mini-player">
      <div className="mini-header">
        <span className="mini-label">{label}</span>
        <span className="muted">{formatTime(duration)}</span>
      </div>
      <div className="mini-controls">
        <button className="btn" onClick={togglePlay} disabled={!src}>
          {isPlaying ? "Pause" : "Play"}
        </button>
        <AudioScrubber currentTime={currentTime} duration={duration} onSeek={handleSeek} />
      </div>
      {showWaveform && src ? (
        <WaveformTimeline
          audioUrl={src}
          height={60}
          editable={false}
          currentTime={currentTime}
          onSeek={handleSeek}
        />
      ) : null}
      <audio ref={audioRef} src={src || undefined} preload="metadata" />
    </div>
  );
};

export default MiniPlayer;
