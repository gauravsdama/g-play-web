export type RootName = "Library" | "Edited" | "Playlists";

export type TreeEntry = {
  name: string;
  type: "dir" | "file";
  path: string;
  title?: string | null;
  artist?: string | null;
  thumbnail?: string | null;
  added_at?: number | null;
  source?: string | null;
};

export type Track = {
  root: RootName;
  path: string;
  title?: string | null;
  artist?: string | null;
  thumbnail?: string | null;
  source?: string | null;
};

export type PartyQueueItem = {
  id: string;
  track: Track;
};

export type ViewName =
  | "Home"
  | "NowPlaying"
  | "Download"
  | "Tuning"
  | "Visualizer"
  | "Playlists"
  | "CreatePlaylist"
  | "Party";

export type VisualizerMode =
  | "Trippy/Psychedelic"
  | "Chill"
  | "Sleepy"
  | "Wakeful"
  | "Electronic"
  | "Beachy/Tropical";
