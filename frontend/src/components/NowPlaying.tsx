import { useEffect, useState } from "react";
import AudioScrubber from "./AudioScrubber";
import WaveformTimeline from "./WaveformTimeline";
import { Track } from "../types";

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

const PrevIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M6 5h2v14H6zM9 12l9 6.5v-13L9 12z" fill="currentColor" />
  </svg>
);

const NextIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M16 5h2v14h-2zM15 12L6 5.5v13L15 12z" fill="currentColor" />
  </svg>
);

type NowPlayingProps = {
  track: Track | null;
  isPlaying: boolean;
  expanded: boolean;
  onTogglePlay: () => void;
  onSkipBack: () => void;
  onSkipNext: () => void;
  onToggleExpanded: () => void;
  onOpenNowPlaying: () => void;
  onOpenParty: () => void;
  onOpenVisualizer: () => void;
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
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
  audioUrl: string | null;
  upNextTitle: string;
};

const NowPlaying = ({
  track,
  isPlaying,
  expanded,
  onTogglePlay,
  onSkipBack,
  onSkipNext,
  onToggleExpanded,
  onOpenNowPlaying,
  onOpenParty,
  onOpenVisualizer,
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
  currentTime,
  duration,
  onSeek,
  audioUrl,
  upNextTitle,
}: NowPlayingProps) => {
  const [renameValue, setRenameValue] = useState("");
  const [renameStatus, setRenameStatus] = useState<string | null>(null);
  const [saveStatus, setSaveStatus] = useState<string | null>(null);
  const [playlistTarget, setPlaylistTarget] = useState("");
  const [playlistStatus, setPlaylistStatus] = useState<string | null>(null);
  const trackFileName = track?.path.split("/").pop() || "";
  const isAlreadyInPlaylist =
    !!playlistTarget && !!trackFileName && !!playlistContents[playlistTarget]?.has(trackFileName);
  const title = track?.title || track?.path?.split("/").pop() || "No track selected";
  const artist = track?.artist || "";
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
    if (track) {
      setRenameValue(track.title || track.path.split("/").pop() || "");
    } else {
      setRenameValue("");
    }
    setRenameStatus(null);
    setSaveStatus(null);
    setPlaylistStatus(null);
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
    <section className={`now-playing ${expanded ? "expanded" : ""}`}>
      <div className="now-playing-card" onClick={onOpenNowPlaying}>
        <div className="now-playing-art">
          {track?.thumbnail ? (
            <img src={track.thumbnail} alt={title} />
          ) : (
            <div className="now-playing-placeholder">G</div>
          )}
        </div>
        <div className="now-playing-info">
          <p className="now-playing-label">Now Playing</p>
          <h2>{title}</h2>
          <p className="now-playing-artist">{artist || "Unknown artist"}</p>
          {track ? (
            <p className="now-playing-meta">
              {tunedLabel} · {sourceLabel}
            </p>
          ) : null}
        </div>
        <div className="now-playing-actions">
          <div className="transport-controls">
            <div className="transport-buttons">
              <button
                className="btn icon ghost"
                onClick={(event) => {
                  event.stopPropagation();
                  onSkipBack();
                }}
                aria-label="Previous track"
                disabled={!track}
              >
                <PrevIcon />
              </button>
              <button
                className="btn icon primary now-play-btn"
                onClick={(event) => {
                  event.stopPropagation();
                  onTogglePlay();
                }}
                aria-label={isPlaying ? "Pause" : "Play"}
              >
                {isPlaying ? <PauseIcon /> : <PlayIcon />}
              </button>
              <button
                className="btn icon ghost"
                onClick={(event) => {
                  event.stopPropagation();
                  onSkipNext();
                }}
                aria-label="Next track"
                disabled={queue.length === 0}
              >
                <NextIcon />
              </button>
            </div>
            <p className="transport-meta">Up next: {upNextTitle}</p>
          </div>
        </div>
      </div>
      <div className="now-scrub">
        <AudioScrubber currentTime={currentTime} duration={duration} onSeek={onSeek} />
        <WaveformTimeline
          audioUrl={audioUrl}
          height={56}
          editable={false}
          currentTime={currentTime}
          onSeek={onSeek}
        />
      </div>
      <button className="expand-strip" onClick={onToggleExpanded}>
        <span className="expand-arrows">V V V</span>
        <span>{expanded ? "Collapse" : "Expand"}</span>
        <span className="expand-arrows">V V V</span>
      </button>
      {expanded ? (
        <div className="now-playing-expanded">
          <div className="now-playing-expanded-actions">
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
                  if (!track) {
                    return;
                  }
                  setSaveStatus("Saving...");
                  try {
                    await onSaveToLibrary(track);
                    setSaveStatus("Saved to Library.");
                  } catch (error) {
                    setSaveStatus((error as Error).message);
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
                  if (!track) {
                    return;
                  }
                  setSaveStatus("Deleting...");
                  try {
                    await onDeleteTrack(track);
                    setSaveStatus("Deleted.");
                  } catch (error) {
                    setSaveStatus((error as Error).message);
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
            {saveStatus ? <p className="status">{saveStatus}</p> : null}
            {playlistStatus ? <p className="status">{playlistStatus}</p> : null}
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
          <div
            className="party-panel"
            onClick={() => {
              onOpenParty();
            }}
          >
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
        </div>
      ) : null}
    </section>
  );
};

export default NowPlaying;
