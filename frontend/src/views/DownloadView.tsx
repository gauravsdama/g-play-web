import { ChangeEvent, useEffect, useMemo, useState } from "react";
import { downloadTrack, fetchYtInfo, uploadFile } from "../api";
import { Track } from "../types";

type DownloadViewProps = {
  playlists: string[];
  onTrackDownloaded: (track: Track) => void;
  onUploadComplete: () => void;
};

const QUALITY_OPTIONS = [96, 128, 160, 192, 256, 320];

const formatDuration = (seconds?: number) => {
  if (!seconds) {
    return "Unknown length";
  }
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
};

const DownloadView = ({ playlists, onTrackDownloaded, onUploadComplete }: DownloadViewProps) => {
  const [url, setUrl] = useState("");
  const [playlist, setPlaylist] = useState("");
  const [qualityIndex, setQualityIndex] = useState(QUALITY_OPTIONS.length - 1);
  const [status, setStatus] = useState<string | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [info, setInfo] = useState<{
    title?: string | null;
    artist?: string | null;
    duration?: number | null;
  } | null>(null);

  const qualityKbps = QUALITY_OPTIONS[qualityIndex];

  useEffect(() => {
    if (!url.trim()) {
      setInfo(null);
      return;
    }
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const data = await fetchYtInfo(url.trim(), controller.signal);
        setInfo(data);
      } catch (error) {
        if ((error as Error).name !== "AbortError") {
          setInfo(null);
        }
      }
    }, 700);
    return () => {
      controller.abort();
      clearTimeout(timer);
    };
  }, [url]);

  const estimatedSize = useMemo(() => {
    if (!info?.duration) {
      return null;
    }
    const sizeMb = (qualityKbps * info.duration) / 8 / 1024;
    return `${sizeMb.toFixed(1)} MB`;
  }, [info?.duration, qualityKbps]);

  const handleDownload = async () => {
    if (!url.trim()) {
      setStatus("Paste a YouTube URL first.");
      return;
    }
    setIsLoading(true);
    setStatus(null);
    setWarning(null);
    try {
      const data = await downloadTrack(url.trim(), playlist || null, qualityKbps);
      setStatus("Download complete.");
      setWarning(data.warning || null);
      onTrackDownloaded({
        root: "Library",
        path: data.path,
        title: data.title,
        artist: data.artist,
        thumbnail: data.thumbnail,
        source: data.source || "youtube",
      });
      setUrl("");
      onUploadComplete();
    } catch (error) {
      setStatus((error as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleUpload = async (event: ChangeEvent<HTMLInputElement>) => {
    const files = event.target.files;
    if (!files?.length) {
      return;
    }
    setStatus("Uploading files...");
    try {
      await Promise.all(Array.from(files).map((file) => uploadFile(file, "Library")));
      setStatus("Upload complete.");
      onUploadComplete();
    } catch (error) {
      setStatus((error as Error).message);
    } finally {
      event.target.value = "";
    }
  };

  return (
    <div className="view">
      <div className="panel">
        <h2>YouTube to MP3</h2>
        <p className="muted">
          Download official audio or topic uploads for the cleanest quality. Music videos
          often include extra noise.
        </p>
        <div className="field">
          <label>YouTube URL or video ID</label>
          <input
            type="text"
            placeholder="https://youtube.com/watch?v=..."
            value={url}
            onChange={(event) => setUrl(event.target.value)}
          />
        </div>
        <div className="split">
          <div className="field">
            <label>Quality</label>
            <div className="quality-row">
              <input
                type="range"
                min={0}
                max={QUALITY_OPTIONS.length - 1}
                step={1}
                value={qualityIndex}
                onChange={(event) => setQualityIndex(Number(event.target.value))}
              />
              <div className="pill">{qualityKbps}k MP3</div>
            </div>
            <p className="muted">
              {estimatedSize
                ? `Estimated size: ${estimatedSize} (${formatDuration(info?.duration || 0)})`
                : "Enter a URL to estimate size."}
            </p>
          </div>
          <div className="field">
            <label>Save to playlist (optional)</label>
            <select value={playlist} onChange={(event) => setPlaylist(event.target.value)}>
              <option value="">(none)</option>
              {playlists.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </select>
          </div>
        </div>
        <button className="btn primary wide" onClick={handleDownload} disabled={isLoading}>
          {isLoading ? "Downloading..." : "Download to library"}
        </button>
        {warning ? <p className="warning">{warning}</p> : null}
        {status ? <p className="status">{status}</p> : null}
      </div>
      <div className="panel">
        <h3>Upload local audio</h3>
        <p className="muted">
          Add locally edited tracks or audio files from your computer into the library.
        </p>
        <label className="upload" htmlFor="upload-audio">
          Select audio files
        </label>
        <input
          id="upload-audio"
          type="file"
          accept="audio/*"
          multiple
          onChange={handleUpload}
          className="hidden-input"
        />
      </div>
    </div>
  );
};

export default DownloadView;
