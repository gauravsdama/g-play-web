import { RootName, Track, TreeEntry } from "./types";

const API_BASE = import.meta.env.VITE_API_BASE ?? "";

const apiUrl = (path: string) => `${API_BASE}${path}`;

export const buildFileUrl = (track: Track) =>
  apiUrl(
    `/api/file?root=${encodeURIComponent(track.root)}&path=${encodeURIComponent(track.path)}`
  );

export const fetchTree = async (root: RootName, path: string) => {
  const url = apiUrl(
    `/api/tree?root=${encodeURIComponent(root)}&path=${encodeURIComponent(path)}`
  );
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Tree load failed: ${res.status}`);
  }
  const data = await res.json();
  return data.entries as TreeEntry[];
};

export const downloadTrack = async (
  url: string,
  playlist?: string | null,
  qualityKbps: number = 320
) => {
  const res = await fetch(apiUrl("/api/download"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ url, playlist: playlist || null, quality_kbps: qualityKbps }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Download failed");
  }
  return res.json();
};

export const fetchYtInfo = async (url: string, signal?: AbortSignal) => {
  const res = await fetch(apiUrl("/api/yt-info"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ url }),
    signal,
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Info fetch failed");
  }
  return res.json();
};

export const fetchAudioProfile = async (root: RootName, path: string) => {
  const res = await fetch(apiUrl("/api/audio-profile"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path, min_coverage: 0.02 }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Audio profile failed");
  }
  return res.json();
};

export const fetchTrackMeta = async (root: RootName, path: string) => {
  const res = await fetch(apiUrl("/api/track-meta"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Track metadata failed");
  }
  return res.json();
};

export const uploadFile = async (file: File, root: RootName) => {
  const form = new FormData();
  form.append("file", file);
  const res = await fetch(apiUrl(`/api/upload?root=${encodeURIComponent(root)}`), {
    method: "POST",
    body: form,
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Upload failed");
  }
  return res.json();
};

export const tuneTrack = async (payload: Record<string, unknown>) => {
  const res = await fetch(apiUrl("/api/tune"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Tune failed");
  }
  return res.json();
};

export const createPlaylist = async (name: string) => {
  const res = await fetch(apiUrl("/api/playlists"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Playlist create failed");
  }
  return res.json();
};

export const renameTrack = async (root: RootName, path: string, newName: string) => {
  const res = await fetch(apiUrl("/api/rename"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path, new_name: newName }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Rename failed");
  }
  return res.json();
};

export const saveToLibrary = async (root: RootName, path: string) => {
  const res = await fetch(apiUrl("/api/save-to-library"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Save to library failed");
  }
  return res.json();
};

export const addToPlaylist = async (playlist: string, root: RootName, path: string) => {
  const res = await fetch(apiUrl("/api/playlists/add"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ playlist, root, path }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Add to playlist failed");
  }
  return res.json();
};

export const applyCuts = async (root: RootName, path: string, cuts: { start: number; end: number }[]) => {
  const res = await fetch(apiUrl("/api/edit-cuts"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path, cuts }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Edit failed");
  }
  return res.json();
};

export const deleteTrack = async (root: RootName, path: string) => {
  const res = await fetch(apiUrl("/api/delete"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Delete failed");
  }
  return res.json();
};

export const openFolder = async (root: RootName, path?: string) => {
  const res = await fetch(apiUrl("/api/open-folder"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ root, path: path || null }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Open folder failed");
  }
  return res.json();
};

export const startParty = async () => {
  const res = await fetch(apiUrl("/api/party/start"), { method: "POST" });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Party start failed");
  }
  return res.json();
};

export const stopParty = async () => {
  const res = await fetch(apiUrl("/api/party/stop"), { method: "POST" });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail || "Party stop failed");
  }
  return res.json();
};

export const partyQueue = async (code: string) => {
  const res = await fetch(apiUrl("/api/party/queue"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    const error = new Error(detail.detail || "Party queue failed") as Error & {
      status?: number;
    };
    error.status = res.status;
    throw error;
  }
  return res.json();
};

export const partyEnqueue = async (code: string, url: string, qualityKbps: number = 320) => {
  const res = await fetch(apiUrl("/api/party/enqueue"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code, url, quality_kbps: qualityKbps }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    const error = new Error(detail.detail || "Party enqueue failed") as Error & {
      status?: number;
    };
    error.status = res.status;
    throw error;
  }
  return res.json();
};
