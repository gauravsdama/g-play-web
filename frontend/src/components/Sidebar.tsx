import { RootName, Track, ViewName } from "../types";
import TreeView from "./TreeView";

const navItems: { id: ViewName; label: string }[] = [
  { id: "Home", label: "Home" },
  { id: "NowPlaying", label: "Now Playing" },
  { id: "Download", label: "Download" },
  { id: "Tuning", label: "Tuning" },
  { id: "Visualizer", label: "Visualizer" },
  { id: "Party", label: "Party Room" },
  { id: "Playlists", label: "Playlists" },
];

const roots: { id: RootName; label: string }[] = [
  { id: "Library", label: "Library" },
  { id: "Edited", label: "Edited (temp)" },
  { id: "Playlists", label: "Playlists" },
];

type SidebarProps = {
  view: ViewName;
  onNavigate: (view: ViewName) => void;
  root: RootName;
  onRootChange: (root: RootName) => void;
  currentPath: string;
  onPathChange: (path: string) => void;
  refreshToken: number;
  librarySort: "recent" | "name";
  onLibrarySortChange: (mode: "recent" | "name") => void;
  onSelectTrack: (track: Track) => void;
  onPlayTrack: (track: Track) => void;
  onSaveToLibrary: (track: Track) => Promise<void>;
  onDeleteTrack: (track: Track) => Promise<void>;
  onOpenFolder: (track: Track) => Promise<void>;
  onAddToQueue: (track: Track) => void;
  onPlayNext: (track: Track) => void;
};

const Sidebar = ({
  view,
  onNavigate,
  root,
  onRootChange,
  currentPath,
  onPathChange,
  refreshToken,
  librarySort,
  onLibrarySortChange,
  onSelectTrack,
  onPlayTrack,
  onSaveToLibrary,
  onDeleteTrack,
  onOpenFolder,
  onAddToQueue,
  onPlayNext,
}: SidebarProps) => {
  const breadcrumbs = currentPath ? currentPath.split("/") : [];
  let cursor = "";

  return (
    <aside className="sidebar">
      <div className="brand">
        <span className="brand-pill">G Play</span>
      </div>
      <div className="nav-section">
        <p className="section-label">Navigation</p>
        <div className="nav-buttons">
          {navItems.map((item, index) => (
            <button
              key={item.id}
              className={`nav-button ${view === item.id ? "active" : ""}`}
              style={{ animationDelay: `${index * 60}ms` }}
              onClick={() => onNavigate(item.id)}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>
      <div className="nav-divider" />
      <div className="explorer-section">
        <p className="section-label">Explorer</p>
        {root === "Library" ? (
          <div className="sort-row">
            <label>Sort</label>
            <select
              value={librarySort}
              onChange={(event) => onLibrarySortChange(event.target.value as "recent" | "name")}
            >
              <option value="recent">Last added</option>
              <option value="name">Name (A-Z)</option>
            </select>
          </div>
        ) : null}
        <div className="root-tabs">
          {roots.map((entry, index) => (
            <button
              key={entry.id}
              className={`root-tab ${root === entry.id ? "active" : ""}`}
              style={{ animationDelay: `${index * 40}ms` }}
              onClick={() => onRootChange(entry.id)}
            >
              {entry.label}
            </button>
          ))}
        </div>
        <div className="breadcrumbs">
          <button
            className={`crumb ${currentPath === "" ? "active" : ""}`}
            onClick={() => onPathChange("")}
          >
            {root}
          </button>
          {breadcrumbs.map((part, index) => {
            cursor = cursor ? `${cursor}/${part}` : part;
            const isActive = cursor === currentPath;
            return (
              <button
                key={cursor}
                className={`crumb ${isActive ? "active" : ""}`}
                onClick={() => onPathChange(cursor)}
              >
                {part}
              </button>
            );
          })}
        </div>
        <TreeView
          root={root}
          currentPath={currentPath}
          refreshToken={refreshToken}
          sortMode={root === "Library" ? librarySort : "name"}
          onPathChange={onPathChange}
          onSelectTrack={onSelectTrack}
          onPlayTrack={onPlayTrack}
          onSaveToLibrary={onSaveToLibrary}
          onDeleteTrack={onDeleteTrack}
          onOpenFolder={onOpenFolder}
          onAddToQueue={onAddToQueue}
          onPlayNext={onPlayNext}
        />
      </div>
    </aside>
  );
};

export default Sidebar;
