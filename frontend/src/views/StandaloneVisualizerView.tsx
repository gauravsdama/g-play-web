import { useEffect, useRef, useState } from "react";
import VisualizerView, { VisualizerFrame, VisualizerSyncState } from "./VisualizerView";
import { Track, VisualizerMode } from "../types";

const CHANNEL_NAME = "gplay-visualizer";

const StandaloneVisualizerView = () => {
  const frameRef = useRef<VisualizerFrame | null>(null);
  const [track, setTrack] = useState<Track | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [mode, setMode] = useState<VisualizerMode>("Chill");
  const [genre, setGenre] = useState("Electronic");
  const [visualizerAuto, setVisualizerAuto] = useState(true);
  const [useArtworkColors, setUseArtworkColors] = useState(true);
  const [syncState, setSyncState] = useState<VisualizerSyncState | null>(null);
  const [supported, setSupported] = useState(true);

  useEffect(() => {
    if (typeof BroadcastChannel === "undefined") {
      setSupported(false);
      return;
    }
    const channel = new BroadcastChannel(CHANNEL_NAME);
    channel.onmessage = (event) => {
      const payload = event.data;
      if (!payload) {
        return;
      }
      if (payload.type === "frame" && payload.frame) {
        frameRef.current = payload.frame as VisualizerFrame;
        return;
      }
      if (payload.type === "state") {
        setTrack(payload.track ?? null);
        setIsPlaying(Boolean(payload.isPlaying));
        if (payload.mode) {
          setMode(payload.mode as VisualizerMode);
        }
        if (payload.genre) {
          setGenre(payload.genre as string);
        }
        setVisualizerAuto(Boolean(payload.visualizerAuto));
        setUseArtworkColors(Boolean(payload.useArtworkColors));
        setSyncState({
          barCount: payload.barCount,
          smoothing: payload.smoothing,
          barColor: payload.barColor,
          glow: payload.glow,
          autoScale: payload.autoScale,
          manualMaxHz: payload.manualMaxHz,
          detectedMaxHz: payload.detectedMaxHz ?? null,
        });
      }
    };
    channel.postMessage({ type: "request_state" });
    return () => channel.close();
  }, []);

  if (!supported) {
    return (
      <div className="party-guest">
        <div className="party-card">
          <h2>Visualizer Pop-out</h2>
          <p className="muted">
            This browser does not support BroadcastChannel. Open the pop-out in a modern
            Chromium or Firefox browser.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="standalone-shell">
      <VisualizerView
        track={track}
        isPlaying={isPlaying}
        ensureAnalyser={async () => null}
        mode={mode}
        genre={genre}
        visualizerAuto={visualizerAuto}
        onVisualizerAutoChange={setVisualizerAuto}
        onGenreChange={setGenre}
        onModeChange={setMode}
        useArtworkColors={useArtworkColors}
        onUseArtworkColorsChange={setUseArtworkColors}
        standalone
        externalFrameRef={frameRef}
        syncState={syncState}
      />
    </div>
  );
};

export default StandaloneVisualizerView;
