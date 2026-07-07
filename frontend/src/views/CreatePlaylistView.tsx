import { useState } from "react";
import { Track } from "../types";

type CreatePlaylistViewProps = {
  onSubmit: (name: string) => Promise<void>;
  onCancel: () => void;
  libraryTracks: Track[];
  onAddTrack: (playlist: string, track: Track) => Promise<void>;
};

const CreatePlaylistView = ({ onSubmit, onCancel, libraryTracks, onAddTrack }: CreatePlaylistViewProps) => {
  const [name, setName] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [created, setCreated] = useState(false);
  const [adding, setAdding] = useState<string | null>(null);
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
  const classMap = new Map<string, string>();
  libraryTracks.forEach((track) => {
    const tuneCount = (track.path.match(/_gplay_tuned/g) || []).length;
    const hasCut = /_cut(\b|_|\d)/i.test(track.path);
    const editCount = tuneCount + (hasCut ? 1 : 0);
    const variantClass =
      editCount > 1 ? "track-tuned-multi" : editCount === 1 ? "track-tuned" : "track-original";
    const sourceHint = track.source || (track.thumbnail ? "youtube" : "");
    const sourceClass =
      sourceHint === "youtube" ? "source-youtube" : sourceHint === "local" ? "source-local" : "";
    classMap.set(track.path, `${variantClass} ${sourceClass}`.trim());
  });

  const handleSubmit = async () => {
    if (!name.trim()) {
      setStatus("Name your playlist first.");
      return;
    }
    setStatus("Creating playlist...");
    try {
      await onSubmit(name.trim());
      setStatus("Playlist created. Add songs below.");
      setCreated(true);
    } catch (error) {
      setStatus((error as Error).message);
    }
  };

  return (
    <div className="view">
      <div className="panel">
        <h2>Create Playlist</h2>
        <p className="muted">Playlists are stored as folders inside your playlists directory.</p>
        <div className="field">
          <label>Playlist name</label>
          <input
            type="text"
            placeholder="Late Night Drives"
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
        </div>
        <div className="button-row">
          <button className="btn primary" onClick={handleSubmit}>
            {created ? "Created" : "Create"}
          </button>
          <button className="btn ghost" onClick={onCancel}>
            Back
          </button>
        </div>
        {status ? <p className="status">{status}</p> : null}
        {created ? (
          <div className="playlist-track-list">
            {libraryTracks.length === 0 ? (
              <p className="muted">No songs in library yet.</p>
            ) : (
              libraryTracks.map((track) => (
                <div
                  key={`${track.root}-${track.path}`}
                  className={`playlist-track ${classMap.get(track.path) || ""}`}
                >
                  <div>
                    <p>{labelMap.get(track.path) || track.title || track.path}</p>
                    <p className="muted">{track.artist || "Unknown artist"}</p>
                  </div>
                  <button
                    className="btn ghost"
                    disabled={adding === track.path}
                    onClick={async () => {
                      if (!name.trim()) {
                        setStatus("Name your playlist first.");
                        return;
                      }
                      setAdding(track.path);
                      try {
                        await onAddTrack(name.trim(), track);
                        setStatus("Added to playlist.");
                      } catch (error) {
                        setStatus((error as Error).message);
                      } finally {
                        setAdding(null);
                      }
                    }}
                  >
                    +
                  </button>
                </div>
              ))
            )}
          </div>
        ) : null}
      </div>
    </div>
  );
};

export default CreatePlaylistView;
