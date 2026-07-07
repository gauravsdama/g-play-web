import { useEffect, useState } from "react";
import AudioScrubber from "../components/AudioScrubber";
import WaveformTimeline from "../components/WaveformTimeline";
import { Track, VisualizerMode } from "../types";

const PlayIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M8 5.5v13l10-6.5-10-6.5z" fill="currentColor" />
  </svg>
);

const PauseIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <rect x="6" y="5" width="4" height="14" rx="1.5" fill="currentColor" />
    <rect x="14" y="5" width="4" height="14" rx="1.5" fill="currentColor" />
  </svg>
);

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

type NowPlayingViewProps = {
  track: Track | null;
  isPlaying: boolean;
  onTogglePlay: () => void;
  onOpenVisualizer: () => void;
  onOpenParty: () => void;
  onOpenTune: () => void;
  onRename: (name: string) => Promise<void>;
  onSaveToLibrary: (track: Track) => Promise<void>;
  onDeleteTrack: (track: Track) => Promise<void>;
  queue: Track[];
  onQueueRemove: (index: number) => void;
  onQueueClear: () => void;
  partyActive: boolean;
  partyCode: string | null;
  partyUrl: string | null;
  partyStatus: string | null;
  onPartyStart: () => void;
  onPartyStop: () => void;
  playlists: string[];
  onAddToPlaylist: (playlist: string, track: Track) => Promise<void>;
  playlistContents: Record<string, Set<string>>;
  genre: string;
  onGenreChange: (genre: string) => void;
  visualizerAuto: boolean;
  onVisualizerAutoChange: (value: boolean) => void;
  visualizerMode: VisualizerMode;
  onVisualizerModeChange: (mode: VisualizerMode) => void;
  useArtworkColors: boolean;
  onUseArtworkColorsChange: (value: boolean) => void;
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
  audioUrl: string | null;
};

const NowPlayingView = ({
  track,
  isPlaying,
  onTogglePlay,
  onOpenVisualizer,
  onOpenParty,
  onOpenTune,
  onRename,
  onSaveToLibrary,
  onDeleteTrack,
  queue,
  onQueueRemove,
  onQueueClear,
  partyActive,
  partyCode,
  partyUrl,
  partyStatus,
  onPartyStart,
  onPartyStop,
  playlists,
  onAddToPlaylist,
  playlistContents,
  genre,
  onGenreChange,
  visualizerAuto,
  onVisualizerAutoChange,
  visualizerMode,
  onVisualizerModeChange,
  useArtworkColors,
  onUseArtworkColorsChange,
  currentTime,
  duration,
  onSeek,
  audioUrl,
}: NowPlayingViewProps) => {
  const [saveStatus, setSaveStatus] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [renameStatus, setRenameStatus] = useState<string | null>(null);
  const [playlistTarget, setPlaylistTarget] = useState("");
  const [playlistStatus, setPlaylistStatus] = useState<string | null>(null);
  const trackFileName = track?.path.split("/").pop() || "";
  const isAlreadyInPlaylist =
    !!playlistTarget && !!trackFileName && !!playlistContents[playlistTarget]?.has(trackFileName);
  const title = track?.title || track?.path?.split("/").pop() || "No track selected";
  const artist = track?.artist || "Unknown artist";
  const tuneCount = track?.path ? (track.path.match(/_gplay_tuned/g) || []).length : 0;
  const hasCut = track?.path ? /_cut(\b|_|\d)/i.test(track.path) : false;
  const editCount = tuneCount + (hasCut ? 1 : 0);
  const tunedLabel = editCount > 0 ? (editCount > 1 ? "Tuned x2+" : "Tuned") : "Original";
  const sourceLabel =
    track?.source === "youtube"
      ? "YouTube"
      : track?.source === "local"
      ? "Local file"
      : track?.thumbnail
      ? "YouTube"
      : "Unknown source";

  useEffect(() => {
    setSaveStatus(null);
    setPlaylistStatus(null);
    if (track) {
      setRenameValue(track.title || track.path.split("/").pop() || "");
    } else {
      setRenameValue("");
    }
    setRenameStatus(null);
  }, [track]);

  const handleRename = async () => {
    if (!track) {
      return;
    }
    if (!renameValue.trim()) {
      setRenameStatus("Name cannot be empty.");
      return;
    }
    setRenameStatus("Renaming...");
    try {
      await onRename(renameValue.trim());
      setRenameStatus("Renamed.");
    } catch (error) {
      setRenameStatus((error as Error).message);
    }
  };

  return (
    <div className="view now-view">
      <div className="now-hero">
        <div className="now-artwork">
          {track?.thumbnail ? (
            <img src={track.thumbnail} alt={title} />
          ) : (
            <div className="now-artwork-placeholder">G</div>
          )}
        </div>
        <div className="now-panel">
          <p className="now-label">Now Playing</p>
          <h2>{title}</h2>
          <p className="muted">{artist}</p>
          {track ? (
            <p className="now-playing-meta">
              {tunedLabel} · {sourceLabel}
            </p>
          ) : null}
          <div className="now-actions">
            <button
              className="btn icon primary now-play-btn large"
              onClick={onTogglePlay}
              aria-label={isPlaying ? "Pause" : "Play"}
            >
              {isPlaying ? <PauseIcon /> : <PlayIcon />}
            </button>
            <button className="btn ghost" onClick={onOpenVisualizer}>
              Open Visualizer
            </button>
            <button className="btn ghost" onClick={onOpenTune}>
              Tune This Song
            </button>
            {track?.root === "Edited" ? (
              <button
                className="btn ghost"
                onClick={async () => {
                  if (track) {
                    setSaveStatus("Saving...");
                    try {
                      await onSaveToLibrary(track);
                      setSaveStatus("Saved to Library.");
                    } catch (error) {
                      setSaveStatus((error as Error).message);
                    }
                  }
                }}
              >
                Save to Library
              </button>
            ) : null}
            {track?.root === "Edited" ? (
              <button
                className="btn ghost"
                onClick={async () => {
                  if (track) {
                    setSaveStatus("Deleting...");
                    try {
                      await onDeleteTrack(track);
                      setSaveStatus("Deleted.");
                    } catch (error) {
                      setSaveStatus((error as Error).message);
                    }
                  }
                }}
              >
                Delete Edited File
              </button>
            ) : null}
            {track && playlists.length > 0 ? (
              <div className="playlist-add">
                <select
                  value={playlistTarget}
                  onChange={(event) => setPlaylistTarget(event.target.value)}
                >
                  <option value="">Add to playlist...</option>
                  {playlists.map((name) => (
                    <option key={name} value={name}>
                      {name}
                    </option>
                  ))}
                </select>
                <button
                  className="btn ghost"
                  disabled={isAlreadyInPlaylist}
                  onClick={async () => {
                    if (!track || !playlistTarget) {
                      return;
                    }
                    if (isAlreadyInPlaylist) {
                      setPlaylistStatus("Already in playlist.");
                      return;
                    }
                    setPlaylistStatus("Adding...");
                    try {
                      await onAddToPlaylist(playlistTarget, track);
                      setPlaylistStatus("Added to playlist.");
                    } catch (error) {
                      setPlaylistStatus((error as Error).message);
                    }
                  }}
                >
                  Add
                </button>
              </div>
            ) : null}
          </div>
          {saveStatus ? <p className="status">{saveStatus}</p> : null}
          {playlistStatus ? <p className="status">{playlistStatus}</p> : null}
          <AudioScrubber currentTime={currentTime} duration={duration} onSeek={onSeek} />
          <WaveformTimeline
            audioUrl={audioUrl}
            height={70}
            editable={false}
            currentTime={currentTime}
            onSeek={onSeek}
          />
          <div className="now-settings">
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
              <label>Auto visualizer from genre</label>
              <input
                type="checkbox"
                checked={visualizerAuto}
                onChange={(event) => onVisualizerAutoChange(event.target.checked)}
              />
            </div>
            <div className="field">
              <label>Visualizer mode</label>
              <select
                value={visualizerMode}
                onChange={(event) => onVisualizerModeChange(event.target.value as VisualizerMode)}
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
          </div>
          <div className="queue-panel">
            <div className="queue-header">
              <div>
                <p className="muted">Up Next</p>
                <h4>Queue</h4>
              </div>
              {queue.length > 0 ? (
                <button className="btn ghost" onClick={onQueueClear}>
                  Clear
                </button>
              ) : null}
            </div>
            {queue.length === 0 ? (
              <p className="muted">Queue is empty.</p>
            ) : (
              <div className="queue-list">
                {queue.map((item, index) => (
                  <div key={`${item.root}-${item.path}-${index}`} className="queue-item">
                    <div>
                      <p className="queue-title">{item.title || item.path.split("/").pop()}</p>
                      <p className="queue-artist">{item.artist || "Unknown artist"}</p>
                    </div>
                    <button
                      className="btn ghost"
                      onClick={() => onQueueRemove(index)}
                      aria-label="Remove from queue"
                    >
                      Remove
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
          <div className="party-panel" onClick={onOpenParty}>
            <div className="party-header">
              <div>
                <p className="muted">Party Room</p>
                <h4>{partyActive ? `Room ${partyCode}` : "Party mode off"}</h4>
              </div>
              {partyActive ? (
                <button
                  className="btn ghost"
                  onClick={(event) => {
                    event.stopPropagation();
                    onPartyStop();
                  }}
                >
                  Stop
                </button>
              ) : (
                <button
                  className="btn ghost"
                  onClick={(event) => {
                    event.stopPropagation();
                    onPartyStart();
                  }}
                >
                  Start
                </button>
              )}
            </div>
            {partyActive && partyUrl ? (
              <div className="party-body">
                <div className="party-qr">
                  <img
                    src={`https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(
                      partyUrl
                    )}`}
                    alt="Party QR"
                  />
                </div>
                <div className="party-link">
                  <p className="muted">Share this link:</p>
                  <code>{partyUrl}</code>
                </div>
              </div>
            ) : (
              <p className="muted">
                Start Party Mode to let friends add YouTube links to your queue.
              </p>
            )}
            {partyStatus ? <p className="status">{partyStatus}</p> : null}
          </div>
          <div className="rename-row">
            <label>Rename file</label>
            <div className="rename-controls">
              <input
                type="text"
                value={renameValue}
                onChange={(event) => setRenameValue(event.target.value)}
                placeholder="Artist - Title"
              />
              <button className="btn" onClick={handleRename} disabled={!track}>
                Rename
              </button>
            </div>
            {renameStatus ? <p className="status">{renameStatus}</p> : null}
          </div>
        </div>
      </div>
    </div>
  );
};

export default NowPlayingView;
