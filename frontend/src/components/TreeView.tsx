import { useEffect, useMemo, useState } from "react";
import { fetchTree } from "../api";
import { RootName, Track, TreeEntry } from "../types";

const AUDIO_EXTENSIONS = [".mp3", ".wav", ".flac", ".m4a", ".ogg"];

type TreeViewProps = {
  root: RootName;
  currentPath: string;
  refreshToken: number;
  sortMode: "recent" | "name";
  onPathChange: (path: string) => void;
  onSelectTrack: (track: Track) => void;
  onPlayTrack: (track: Track) => void;
  onSaveToLibrary: (track: Track) => Promise<void>;
  onDeleteTrack: (track: Track) => Promise<void>;
  onOpenFolder: (track: Track) => Promise<void>;
  onAddToQueue: (track: Track) => void;
  onPlayNext: (track: Track) => void;
};

type CacheMap = Record<string, TreeEntry[]>;

const keyFor = (root: RootName, path: string) => `${root}:${path || ""}`;

const TreeView = ({
  root,
  currentPath,
  refreshToken,
  sortMode,
  onPathChange,
  onSelectTrack,
  onPlayTrack,
  onSaveToLibrary,
  onDeleteTrack,
  onOpenFolder,
  onAddToQueue,
  onPlayNext,
}: TreeViewProps) => {
  const [cache, setCache] = useState<CacheMap>({});
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    track: Track;
  } | null>(null);
  const [menuStatus, setMenuStatus] = useState<string | null>(null);

  const loadPath = async (path: string) => {
    const key = keyFor(root, path);
    if (cache[key]) {
      return;
    }
    try {
      const entries = await fetchTree(root, path);
      setCache((prev) => ({ ...prev, [key]: entries }));
    } catch (error) {
      console.error(error);
    }
  };

  const ensureExpanded = (path: string) => {
    const segments = path ? path.split("/") : [];
    let cursor = "";
    const nextExpanded = new Set(expanded);
    nextExpanded.add(keyFor(root, ""));
    loadPath("");
    segments.forEach((segment) => {
      cursor = cursor ? `${cursor}/${segment}` : segment;
      nextExpanded.add(keyFor(root, cursor));
      loadPath(cursor);
    });
    setExpanded(nextExpanded);
  };

  useEffect(() => {
    setCache({});
    setExpanded(new Set([keyFor(root, "")]));
    loadPath("");
    setContextMenu(null);
    setMenuStatus(null);
  }, [root]);

  useEffect(() => {
    ensureExpanded(currentPath);
  }, [currentPath, root]);

  useEffect(() => {
    const handleClick = () => setContextMenu(null);
    window.addEventListener("click", handleClick);
    return () => window.removeEventListener("click", handleClick);
  }, []);

  useEffect(() => {
    setCache({});
    setExpanded(new Set([keyFor(root, "")]));
    loadPath("");
    if (currentPath) {
      ensureExpanded(currentPath);
    }
  }, [refreshToken]);

  const currentEntries = cache[keyFor(root, currentPath)] || [];

  const sortEntries = (entries: TreeEntry[]) => {
    return [...entries].sort((a, b) => {
      if (a.type !== b.type) {
        return a.type === "dir" ? -1 : 1;
      }
      if (a.type === "dir") {
        return a.name.localeCompare(b.name);
      }
      if (sortMode === "recent") {
        const aTime = a.added_at || 0;
        const bTime = b.added_at || 0;
        if (aTime !== bTime) {
          return bTime - aTime;
        }
      }
      return a.name.localeCompare(b.name);
    });
  };

  const sortedCurrent = useMemo(() => sortEntries(currentEntries), [currentEntries, sortMode]);

  const buildDisplayMap = (entries: TreeEntry[]) => {
    const totals = new Map<string, number>();
    const counts = new Map<string, number>();
    const labels = new Map<string, string>();
    entries
      .filter((entry) => entry.type === "file")
      .forEach((entry) => {
        const key = (entry.title || entry.name).toLowerCase();
        totals.set(key, (totals.get(key) || 0) + 1);
      });
    entries
      .filter((entry) => entry.type === "file")
      .forEach((entry) => {
        const base = entry.title || entry.name;
        const key = base.toLowerCase();
        const index = (counts.get(key) || 0) + 1;
        counts.set(key, index);
        const total = totals.get(key) || 0;
        labels.set(entry.path, total > 1 ? `${base} (${index})` : base);
      });
    return labels;
  };

  const currentLabels = useMemo(() => buildDisplayMap(sortedCurrent), [sortedCurrent]);

  const toggleExpanded = (path: string) => {
    const key = keyFor(root, path);
    const nextExpanded = new Set(expanded);
    if (nextExpanded.has(key)) {
      nextExpanded.delete(key);
    } else {
      nextExpanded.add(key);
      loadPath(path);
    }
    setExpanded(nextExpanded);
  };

  const renderEntries = (entries: TreeEntry[], depth: number) => {
    const labels = buildDisplayMap(entries);
    return entries.map((entry, index) => {
      const nodePath = entry.path;
      const nodeKey = keyFor(root, nodePath);
      const isDir = entry.type === "dir";
      const isExpanded = expanded.has(nodeKey);
      const isCurrent = nodePath === currentPath;
      const fileLabel = labels.get(entry.path) || entry.title || entry.name;
      const suffix = entry.name.toLowerCase().split(".").pop() || "";
      const isLossless = ["flac", "wav", "aiff", "alac"].includes(suffix);
      const tuneCount = (entry.name.match(/_gplay_tuned/g) || []).length;
      const hasEditSuffix = /_cut(\b|_|\d)/i.test(entry.name);
      const editCount = tuneCount + (hasEditSuffix ? 1 : 0);
      const variantClass =
        editCount > 1
          ? "track-tuned-multi"
          : editCount === 1
          ? "track-tuned"
          : root === "Library"
          ? "track-original"
          : "";
      const track: Track = {
        root,
        path: nodePath,
        title: entry.title || entry.name,
        artist: entry.artist,
        thumbnail: entry.thumbnail,
        source: entry.source,
      };

      const delay = Math.min(20, index) * 40;

      return (
        <div key={nodeKey}>
          <div
            className={`tree-item ${isDir ? "dir" : "file"} ${variantClass} ${
              isCurrent ? "current" : ""
            } ${isLossless ? "lossless" : ""}`}
            style={{ paddingLeft: 14 + depth * 14, animationDelay: `${delay}ms` }}
            onClick={() => {
              if (isDir) {
                onPathChange(nodePath);
              } else {
                onSelectTrack(track);
              }
            }}
            onDoubleClick={() => {
              if (!isDir) {
                onPlayTrack(track);
              }
            }}
            onContextMenu={(event) => {
              if (!isDir) {
                event.preventDefault();
                setMenuStatus(null);
                setContextMenu({ x: event.clientX, y: event.clientY, track });
              }
            }}
          >
            {isDir ? (
              <button
                className={`tree-toggle ${isExpanded ? "open" : ""}`}
                onClick={(event) => {
                  event.stopPropagation();
                  toggleExpanded(nodePath);
                }}
              >
                {isExpanded ? "v" : ">"}
              </button>
            ) : (
              <span className="tree-dot" />
            )}
            <div className="tree-label">
              <span className="tree-name">{fileLabel}</span>
              {!isDir ? (
                <span className="tree-artist">{entry.artist || "Unknown artist"}</span>
              ) : null}
            </div>
          </div>
          {isDir && isExpanded ? (
            <div className="tree-branch">
              {renderEntries(cache[nodeKey] || [], depth + 1)}
            </div>
          ) : null}
        </div>
      );
    });
  };

  const rootEntries = cache[keyFor(root, "")] || [];
  const filteredRoot = sortEntries(
    rootEntries.filter((entry) => {
      if (entry.type === "dir") {
        return true;
      }
      const name = entry.name.toLowerCase();
      return AUDIO_EXTENSIONS.some((ext) => name.endsWith(ext));
    })
  );

  return (
    <div className="tree-view">
      <div className="tree-current">
        <div className="tree-current-header">
          <span>Current Folder</span>
          <span className="tree-current-path">{currentPath || root}</span>
        </div>
        <div className="tree-current-list">
          {sortedCurrent.length === 0 ? (
            <div className="tree-empty">No audio files in this folder.</div>
          ) : (
            sortedCurrent.map((entry, index) => {
              if (entry.type === "dir") {
                return (
                  <button
                    key={`${entry.path}-current`}
                    className="tree-current-item dir"
                    style={{ animationDelay: `${index * 40}ms` }}
                    onClick={() => onPathChange(entry.path)}
                  >
                    <span className="tree-folder">DIR</span>
                    <span>{entry.name}</span>
                  </button>
                );
              }
              const suffix = entry.name.toLowerCase().split(".").pop() || "";
              const isLossless = ["flac", "wav", "aiff", "alac"].includes(suffix);
              const tuneCount = (entry.name.match(/_gplay_tuned/g) || []).length;
              const hasEditSuffix = /_cut(\b|_|\d)/i.test(entry.name);
              const editCount = tuneCount + (hasEditSuffix ? 1 : 0);
              const variantClass =
                editCount > 1
                  ? "track-tuned-multi"
                  : editCount === 1
                  ? "track-tuned"
                  : root === "Library"
                  ? "track-original"
                  : "";
              const track: Track = {
                root,
                path: entry.path,
                title: entry.title || entry.name,
                artist: entry.artist,
                thumbnail: entry.thumbnail,
                source: entry.source,
              };
              const showThumb = root === "Library";
              return (
                <button
                  key={`${entry.path}-current`}
                  className={`tree-current-item file ${variantClass} ${isLossless ? "lossless" : ""}`}
                  style={{ animationDelay: `${index * 40}ms` }}
                  onClick={() => onSelectTrack(track)}
                  onDoubleClick={() => onPlayTrack(track)}
                  onContextMenu={(event) => {
                    event.preventDefault();
                    setMenuStatus(null);
                    setContextMenu({ x: event.clientX, y: event.clientY, track });
                  }}
                >
                  {showThumb ? (
                    <div className="tree-thumb">
                      {entry.thumbnail ? (
                        <img src={entry.thumbnail} alt={entry.title || entry.name} />
                      ) : (
                        <div className="tree-thumb-note" aria-hidden="true">
                          <svg viewBox="0 0 24 24">
                            <path
                              d="M14 4v10.1a3.6 3.6 0 1 0 2 3.2V8h4V4h-6z"
                              fill="currentColor"
                            />
                          </svg>
                        </div>
                      )}
                    </div>
                  ) : null}
                  <div className="tree-song-text">
                    <span className="tree-song-title">
                      {currentLabels.get(entry.path) || entry.title || entry.name}
                    </span>
                    <span className="tree-song-artist">{entry.artist || "Unknown artist"}</span>
                  </div>
                </button>
              );
            })
          )}
        </div>
      </div>
      <div className="tree-full">
        <div className="tree-full-header">Explorer</div>
        {renderEntries(filteredRoot, 0)}
      </div>
      {contextMenu ? (
        <div
          className="context-menu"
          style={{ top: contextMenu.y, left: contextMenu.x }}
        >
          <button
            onClick={() => {
              onPlayNext(contextMenu.track);
              setContextMenu(null);
            }}
          >
            Play Next
          </button>
          <button
            onClick={() => {
              onAddToQueue(contextMenu.track);
              setContextMenu(null);
            }}
          >
            Add to Queue
          </button>
          {root === "Edited" ? (
            <button
              onClick={async () => {
                try {
                  await onSaveToLibrary(contextMenu.track);
                  setContextMenu(null);
                } catch (error) {
                  setMenuStatus((error as Error).message);
                }
              }}
            >
              Save to Library
            </button>
          ) : null}
          {root === "Library" ? (
            <button
              onClick={async () => {
                try {
                  await onOpenFolder(contextMenu.track);
                  setContextMenu(null);
                } catch (error) {
                  setMenuStatus((error as Error).message);
                }
              }}
            >
              Open in Folder
            </button>
          ) : null}
          {root === "Edited" || root === "Library" ? (
            <button
              onClick={async () => {
                try {
                  await onDeleteTrack(contextMenu.track);
                  setContextMenu(null);
                } catch (error) {
                  setMenuStatus((error as Error).message);
                }
              }}
            >
              Delete File
            </button>
          ) : null}
          {menuStatus ? <p className="menu-status">{menuStatus}</p> : null}
        </div>
      ) : null}
    </div>
  );
};

export default TreeView;
