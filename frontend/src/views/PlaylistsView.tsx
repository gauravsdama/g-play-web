import { useMemo, useState } from "react";
import { tuneTrack } from "../api";
import { PRESETS } from "../tuningPresets";
import { Track } from "../types";

type PlaylistsViewProps = {
  playlists: string[];
  onCreate: () => void;
  onOpenPlaylist: (name: string) => void;
  onPlayPlaylist: (name: string) => Promise<void>;
  libraryTracks: Track[];
  onAddTrack: (playlist: string, track: Track) => Promise<void>;
  playlistContents: Record<string, Set<string>>;
  onRefresh: () => void;
};

const PlaylistsView = ({
  playlists,
  onCreate,
  onOpenPlaylist,
  onPlayPlaylist,
  libraryTracks,
  onAddTrack,
  playlistContents,
  onRefresh,
}: PlaylistsViewProps) => {
  const [activePlaylist, setActivePlaylist] = useState<string | null>(null);
  const [showAddTracks, setShowAddTracks] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [playlistStatus, setPlaylistStatus] = useState<string | null>(null);
  const [eqPreset, setEqPreset] = useState("Flat");
  const [eqStatus, setEqStatus] = useState<string | null>(null);
  const [eqBusy, setEqBusy] = useState(false);
  const buildLabelMap = (tracks: Track[]) => {
    const totals = new Map<string, number>();
    const counts = new Map<string, number>();
    const labels = new Map<string, string>();
    tracks.forEach((track) => {
      const key = (track.title || track.path).toLowerCase();
      totals.set(key, (totals.get(key) || 0) + 1);
    });
    tracks.forEach((track) => {
      const base = track.title || track.path;
      const key = base.toLowerCase();
      const index = (counts.get(key) || 0) + 1;
      counts.set(key, index);
      const total = totals.get(key) || 0;
      labels.set(track.path, total > 1 ? `${base} (${index})` : base);
    });
    return labels;
  };
  const labelMap = buildLabelMap(libraryTracks);
  const classMap = useMemo(() => {
    const map = new Map<string, string>();
    libraryTracks.forEach((track) => {
      const tuneCount = (track.path.match(/_gplay_tuned/g) || []).length;
      const hasCut = /_cut(\b|_|\d)/i.test(track.path);
      const editCount = tuneCount + (hasCut ? 1 : 0);
      const variantClass =
        editCount > 1 ? "track-tuned-multi" : editCount === 1 ? "track-tuned" : "track-original";
      const sourceHint = track.source || (track.thumbnail ? "youtube" : "");
      const sourceClass =
        sourceHint === "youtube" ? "source-youtube" : sourceHint === "local" ? "source-local" : "";
      map.set(track.path, `${variantClass} ${sourceClass}`.trim());
    });
    return map;
  }, [libraryTracks]);
  const presetOptions = useMemo(() => Object.keys(PRESETS), []);
  const playlistTracks = useMemo(() => {
    if (!activePlaylist) {
      return [];
    }
    const entries = playlistContents[activePlaylist];
    if (!entries) {
      return [];
    }
    return Array.from(entries).sort((a, b) => a.localeCompare(b));
  }, [activePlaylist, playlistContents]);

  return (
    <div className="view">
      <div className="panel">
        <div className="split header">
          <div>
            <h2>Playlists</h2>
            <p className="muted">Pick a playlist and add songs from your library.</p>
          </div>
          <button className="btn primary" onClick={onCreate}>
            Create Playlist
          </button>
        </div>
        <div className="playlist-grid">
          {playlists.length === 0 ? (
            <p className="muted">No playlists yet.</p>
          ) : (
            playlists.map((name) => (
              <button
                key={name}
                className={`playlist-card ${activePlaylist === name ? "active" : ""}`}
                onClick={() => {
                  setActivePlaylist(name);
                  setShowAddTracks(false);
                  setStatus(null);
                  setPlaylistStatus(null);
                  setEqStatus(null);
                  onOpenPlaylist(name);
                }}
              >
                <span className="playlist-title">{name}</span>
                <span className="playlist-sub">Tap to open</span>
              </button>
            ))
          )}
        </div>
        {activePlaylist ? (
          <div className="playlist-track-list">
            <div className="playlist-detail-header">
              <div>
                <h3>{activePlaylist}</h3>
                <p className="muted">
                  {playlistTracks.length} {playlistTracks.length === 1 ? "song" : "songs"}
                </p>
              </div>
              <div className="playlist-actions">
                <button
                  className="btn primary"
                  onClick={async () => {
                    setPlaylistStatus("Starting playlist...");
                    try {
                      await onPlayPlaylist(activePlaylist);
                      setPlaylistStatus("Playlist queued.");
                    } catch (error) {
                      setPlaylistStatus((error as Error).message);
                    }
                  }}
                  disabled={playlistTracks.length === 0}
                >
                  Play
                </button>
                <button
                  className="btn ghost"
                  onClick={() => setShowAddTracks((prev) => !prev)}
                >
                  {showAddTracks ? "Hide Add Songs" : "Add Songs"}
                </button>
              </div>
            </div>
            <div className="playlist-eq-row">
              <label>EQ preset</label>
              <select value={eqPreset} onChange={(event) => setEqPreset(event.target.value)}>
                {presetOptions.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
              <button
                className="btn ghost"
                onClick={async () => {
                  if (eqBusy) {
                    return;
                  }
                  if (!activePlaylist || playlistTracks.length === 0) {
                    setEqStatus("Add songs to the playlist first.");
                    return;
                  }
                  const preset = PRESETS[eqPreset];
                  if (!preset) {
                    setEqStatus("Select an EQ preset.");
                    return;
                  }
                  setEqBusy(true);
                  setEqStatus(`Applying ${eqPreset}...`);
                  let successCount = 0;
                  let failCount = 0;
                  for (const file of playlistTracks) {
                    try {
                      await tuneTrack({
                        root: "Playlists",
                        path: `${activePlaylist}/${file}`,
                        preamp_db: preset.preamp ?? 0,
                        eq_gains: preset.eq,
                        spatial_width: preset.spatial / 100,
                        drc_mode: preset.drc,
                        balance: 0,
                        limiter_on: true,
                        preset_name: eqPreset,
                      });
                      successCount += 1;
                    } catch {
                      failCount += 1;
                    }
                  }
                  if (failCount > 0) {
                    setEqStatus(`Applied to ${successCount}. Skipped ${failCount}.`);
                  } else {
                    setEqStatus(`Applied to ${successCount} tracks.`);
                  }
                  setEqBusy(false);
                  onRefresh();
                }}
                disabled={eqBusy || playlistTracks.length === 0}
              >
                Apply EQ
              </button>
            </div>
            {playlistTracks.length === 0 ? (
              <p className="muted">No songs in this playlist yet.</p>
            ) : (
              <div className="playlist-tracks">
                {playlistTracks.map((file) => (
                  <div key={file} className="playlist-track">
                    <div>
                      <p>{file}</p>
                      <p className="muted">In playlist</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
            {showAddTracks ? (
              <div className="playlist-add-panel">
                <h4>Add songs to {activePlaylist}</h4>
                {libraryTracks.length === 0 ? (
                  <p className="muted">No songs in library yet.</p>
                ) : (
                  libraryTracks.map((track) => (
                    <div
                      key={track.path}
                      className={`playlist-track ${classMap.get(track.path) || ""}`}
                    >
                      <div>
                        <p>{labelMap.get(track.path) || track.title || track.path}</p>
                        <p className="muted">{track.artist || "Unknown artist"}</p>
                      </div>
                      <button
                        className="btn ghost"
                        disabled={
                          !!activePlaylist &&
                          !!playlistContents[activePlaylist]?.has(track.path.split("/").pop() || "")
                        }
                        onClick={async () => {
                          setStatus("Adding...");
                          try {
                            await onAddTrack(activePlaylist, {
                              root: "Library",
                              path: track.path,
                              title: track.title,
                              artist: track.artist,
                              thumbnail: track.thumbnail,
                              source: track.source,
                            });
                            setStatus("Added to playlist.");
                          } catch (error) {
                            setStatus((error as Error).message);
                          }
                        }}
                      >
                        +
                      </button>
                    </div>
                  ))
                )}
                {status ? <p className="status">{status}</p> : null}
              </div>
            ) : null}
            {playlistStatus ? <p className="status">{playlistStatus}</p> : null}
            {eqStatus ? <p className="status">{eqStatus}</p> : null}
          </div>
        ) : null}
      </div>
    </div>
  );
};

export default PlaylistsView;
