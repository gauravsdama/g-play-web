import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  addToPlaylist,
  buildFileUrl,
  createPlaylist,
  deleteTrack,
  fetchTree,
  openFolder,
  partyQueue,
  startParty,
  stopParty,
  renameTrack,
  saveToLibrary,
} from "./api";
import NowPlaying from "./components/NowPlaying";
import Sidebar from "./components/Sidebar";
import HomeView from "./views/HomeView";
import NowPlayingView from "./views/NowPlayingView";
import DownloadView from "./views/DownloadView";
import TuningView from "./views/TuningView";
import VisualizerView from "./views/VisualizerView";
import PlaylistsView from "./views/PlaylistsView";
import CreatePlaylistView from "./views/CreatePlaylistView";
import PartyGuestView from "./views/PartyGuestView";
import PartyRoomView from "./views/PartyRoomView";
import { RootName, Track, ViewName, VisualizerMode } from "./types";

const App = () => {
  const [view, setView] = useState<ViewName>("Home");
  const [root, setRoot] = useState<RootName>("Library");
  const [currentPath, setCurrentPath] = useState("");
  const [selectedTrack, setSelectedTrack] = useState<Track | null>(null);
  const [nowPlaying, setNowPlaying] = useState<Track | null>(null);
  const [nowExpanded, setNowExpanded] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [refreshToken, setRefreshToken] = useState(0);
  const [playlists, setPlaylists] = useState<string[]>([]);
  const [playlistContents, setPlaylistContents] = useState<Record<string, Set<string>>>({});
  const [libraryTracks, setLibraryTracks] = useState<Track[]>([]);
  const [librarySort, setLibrarySort] = useState<"recent" | "name">("recent");
  const [genre, setGenre] = useState("Electronic");
  const [visualizerAuto, setVisualizerAuto] = useState(true);
  const [visualizerMode, setVisualizerMode] = useState<VisualizerMode>("Chill");
  const [useArtworkColors, setUseArtworkColors] = useState(true);
  const [queue, setQueue] = useState<Track[]>([]);
  const [history, setHistory] = useState<Track[]>([]);
  const [partyActive, setPartyActive] = useState(false);
  const [partyCode, setPartyCode] = useState<string | null>(null);
  const [partyStatus, setPartyStatus] = useState<string | null>(null);
  const [partyUrl, setPartyUrl] = useState<string | null>(null);
  const [partyHost, setPartyHost] = useState(
    () => window.localStorage.getItem("gplay-party-host") || ""
  );
  const partyGuest = useMemo(
    () => new URLSearchParams(window.location.search).get("party") === "1",
    []
  );

  const audioRef = useRef<HTMLAudioElement>(new Audio());
  const preloadRef = useRef<HTMLAudioElement>(new Audio());
  const queueRef = useRef<Track[]>([]);
  const historyRef = useRef<Track[]>([]);
  const nowPlayingRef = useRef<Track | null>(null);
  const partySeenRef = useRef<Set<string>>(new Set());
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const sourceRef = useRef<MediaElementAudioSourceNode | null>(null);

  const isLocalHost = (host: string) =>
    host === "localhost" || host === "127.0.0.1" || host === "::1";

  const normalizePartyHost = (value: string) => {
    const trimmed = value.trim();
    if (!trimmed) {
      return "";
    }
    try {
      if (trimmed.includes("://")) {
        const parsed = new URL(trimmed);
        return parsed.host;
      }
    } catch {
      return trimmed;
    }
    return trimmed;
  };

  const detectLocalIp = useCallback(async () => {
    if (typeof RTCPeerConnection === "undefined") {
      return null;
    }
    return new Promise<string | null>((resolve) => {
      let resolved = false;
      const peer = new RTCPeerConnection({ iceServers: [] });
      peer.createDataChannel("gplay");
      const cleanup = (value: string | null) => {
        if (resolved) {
          return;
        }
        resolved = true;
        peer.onicecandidate = null;
        peer.close();
        resolve(value);
      };
      const isPrivateIp = (ip: string) => {
        if (ip.startsWith("10.")) {
          return true;
        }
        if (ip.startsWith("192.168.")) {
          return true;
        }
        if (ip.startsWith("172.")) {
          const parts = ip.split(".").map((part) => Number(part));
          return parts[1] >= 16 && parts[1] <= 31;
        }
        return false;
      };
      peer.onicecandidate = (event) => {
        if (!event.candidate) {
          cleanup(null);
          return;
        }
        const match = event.candidate.candidate.match(
          /([0-9]{1,3}(?:\.[0-9]{1,3}){3})/
        );
        if (!match) {
          return;
        }
        const ip = match[1];
        if (ip !== "127.0.0.1" && isPrivateIp(ip)) {
          cleanup(ip);
        }
      };
      peer
        .createOffer()
        .then((offer) => peer.setLocalDescription(offer))
        .catch(() => cleanup(null));
      setTimeout(() => cleanup(null), 1200);
    });
  }, []);

  const resolvePartyHost = useCallback(async () => {
    const currentHost = window.location.hostname;
    if (!isLocalHost(currentHost)) {
      setPartyHost(currentHost);
      return currentHost;
    }
    const cached = window.localStorage.getItem("gplay-party-host");
    if (cached) {
      const normalized = normalizePartyHost(cached);
      setPartyHost(normalized);
      return normalized;
    }
    const detected = await detectLocalIp();
    if (detected) {
      window.localStorage.setItem("gplay-party-host", detected);
      setPartyHost(detected);
      return detected;
    }
    return currentHost;
  }, [detectLocalIp]);

  const buildPartyUrl = useCallback(
    (code: string, hostOverride?: string | null) => {
      const url = new URL(window.location.href);
      if (hostOverride) {
        const normalized = normalizePartyHost(hostOverride);
        if (normalized.includes(":")) {
          const [host, port] = normalized.split(":");
          url.hostname = host;
          if (port) {
            url.port = port;
          }
        } else if (normalized) {
          url.hostname = normalized;
        }
      }
      url.searchParams.set("party", "1");
      url.searchParams.set("code", code);
      url.searchParams.delete("visualizer");
      return url.toString();
    },
    []
  );

  useEffect(() => {
    resolvePartyHost().catch(() => undefined);
  }, [resolvePartyHost]);

  const playTrack = useCallback((track: Track, options?: { fromHistory?: boolean }) => {
    const audio = audioRef.current;
    const current = nowPlayingRef.current;
    if (
      current &&
      !options?.fromHistory &&
      !(current.root === track.root && current.path === track.path)
    ) {
      setHistory((prev) => [...prev, current]);
    }
    const url = buildFileUrl(track);
    audio.src = url;
    audio.play().catch(() => {
      setIsPlaying(false);
    });
    setNowPlaying(track);
    nowPlayingRef.current = track;
  }, []);

  useEffect(() => {
    const audio = audioRef.current;
    audio.preload = "metadata";
    audio.crossOrigin = "anonymous";
    const handlePlay = () => setIsPlaying(true);
    const handlePause = () => setIsPlaying(false);
    const handleTime = () => setCurrentTime(audio.currentTime || 0);
    const handleMeta = () => setDuration(audio.duration || 0);
    const handleEnded = () => {
      setIsPlaying(false);
      const next = queueRef.current[0];
      if (next) {
        setQueue((prev) => prev.slice(1));
        playTrack(next);
      }
    };
    audio.addEventListener("play", handlePlay);
    audio.addEventListener("pause", handlePause);
    audio.addEventListener("timeupdate", handleTime);
    audio.addEventListener("loadedmetadata", handleMeta);
    audio.addEventListener("ended", handleEnded);
    return () => {
      audio.removeEventListener("play", handlePlay);
      audio.removeEventListener("pause", handlePause);
      audio.removeEventListener("timeupdate", handleTime);
      audio.removeEventListener("loadedmetadata", handleMeta);
      audio.removeEventListener("ended", handleEnded);
    };
  }, [playTrack]);

  useEffect(() => {
    const preload = preloadRef.current;
    preload.preload = "auto";
    preload.crossOrigin = "anonymous";
  }, []);

  useEffect(() => {
    queueRef.current = queue;
  }, [queue]);

  useEffect(() => {
    historyRef.current = history;
  }, [history]);

  useEffect(() => {
    nowPlayingRef.current = nowPlaying;
  }, [nowPlaying]);

  useEffect(() => {
    const next = queue[0];
    const preload = preloadRef.current;
    if (!next) {
      preload.removeAttribute("src");
      return;
    }
    const url = buildFileUrl(next);
    if (preload.src !== url) {
      preload.src = url;
      preload.load();
    }
  }, [queue]);

  const ensureAnalyser = useCallback(async () => {
    const audio = audioRef.current;
    if (!audio) {
      return null;
    }
    if (!audioContextRef.current) {
      audioContextRef.current = new AudioContext();
    }
    if (!sourceRef.current) {
      sourceRef.current = audioContextRef.current.createMediaElementSource(audio);
      analyserRef.current = audioContextRef.current.createAnalyser();
      sourceRef.current.connect(analyserRef.current);
      analyserRef.current.connect(audioContextRef.current.destination);
    }
    if (audioContextRef.current.state === "suspended") {
      await audioContextRef.current.resume();
    }
    return analyserRef.current;
  }, []);

  const togglePlay = useCallback(() => {
    if (!nowPlaying) {
      return;
    }
    const audio = audioRef.current;
    if (audio.paused) {
      audio.play().catch(() => {
        setIsPlaying(false);
      });
    } else {
      audio.pause();
    }
  }, [nowPlaying]);

  const refreshTree = useCallback(() => {
    setRefreshToken((prev) => prev + 1);
  }, []);

  const loadPlaylists = useCallback(async () => {
    try {
      const entries = await fetchTree("Playlists", "");
      const names = entries.filter((entry) => entry.type === "dir").map((entry) => entry.name);
      setPlaylists(names);
    } catch (error) {
      console.error(error);
    }
  }, []);

  const loadPlaylistContents = useCallback(async () => {
    if (playlists.length === 0) {
      setPlaylistContents({});
      return;
    }
    try {
      const results = await Promise.all(
        playlists.map(async (name) => {
          const entries = await fetchTree("Playlists", name);
          const files = entries.filter((entry) => entry.type === "file").map((entry) => entry.name);
          return [name, new Set(files)] as const;
        })
      );
      const next: Record<string, Set<string>> = {};
      results.forEach(([name, set]) => {
        next[name] = set;
      });
      setPlaylistContents(next);
    } catch (error) {
      console.error(error);
    }
  }, [playlists]);

  const loadLibraryTracks = useCallback(async () => {
    try {
      const entries = await fetchTree("Library", "");
      const tracks = entries
        .filter((entry) => entry.type === "file")
        .map((entry) => ({
          root: "Library" as const,
          path: entry.path,
          title: entry.title || entry.name,
          artist: entry.artist,
          thumbnail: entry.thumbnail,
          source: entry.source,
        }));
      setLibraryTracks(tracks);
    } catch (error) {
      console.error(error);
    }
  }, []);

  useEffect(() => {
    loadPlaylists();
    loadLibraryTracks();
    loadPlaylistContents();
  }, [loadPlaylists, loadLibraryTracks, loadPlaylistContents, refreshToken]);

  const handleRootChange = (nextRoot: RootName) => {
    setRoot(nextRoot);
    setCurrentPath("");
  };

  const handleTrackDownloaded = (track: Track) => {
    setSelectedTrack(track);
    setNowPlaying(track);
    refreshTree();
  };

  const handleTuneComplete = (track: Track) => {
    setSelectedTrack(track);
    refreshTree();
  };

  const handleCreatePlaylist = async (name: string) => {
    await createPlaylist(name);
    refreshTree();
    setView("Playlists");
  };

  const handleRenameTrack = async (name: string) => {
    if (!nowPlaying) {
      return;
    }
    const data = await renameTrack(nowPlaying.root, nowPlaying.path, name);
    const updated: Track = {
      root: nowPlaying.root,
      path: data.path,
      title: data.title,
      artist: data.artist,
      thumbnail: data.thumbnail,
    };
    setNowPlaying(updated);
    if (selectedTrack?.path === nowPlaying.path && selectedTrack.root === nowPlaying.root) {
      setSelectedTrack(updated);
    }
    const audio = audioRef.current;
    const shouldResume = !audio.paused;
    audio.src = buildFileUrl(updated);
    if (shouldResume) {
      audio.play().catch(() => {
        setIsPlaying(false);
      });
    }
    refreshTree();
  };

  const handleAddToPlaylist = async (playlist: string, track: Track) => {
    await addToPlaylist(playlist, track.root, track.path);
    refreshTree();
  };

  const handleSaveToLibrary = async (track: Track) => {
    const data = await saveToLibrary(track.root, track.path);
    const saved: Track = {
      root: "Library",
      path: data.path,
      title: data.title,
      artist: data.artist,
      thumbnail: data.thumbnail,
    };
    if (nowPlaying?.root === track.root && nowPlaying.path === track.path) {
      setNowPlaying(saved);
      const audio = audioRef.current;
      const shouldResume = !audio.paused;
      audio.src = buildFileUrl(saved);
      if (shouldResume) {
        audio.play().catch(() => {
          setIsPlaying(false);
        });
      }
    }
    if (selectedTrack?.root === track.root && selectedTrack.path === track.path) {
      setSelectedTrack(saved);
    }
    refreshTree();
  };

  const handleDeleteTrack = async (track: Track) => {
    await deleteTrack(track.root, track.path);
    if (nowPlaying?.root === track.root && nowPlaying.path === track.path) {
      setNowPlaying(null);
      audioRef.current.pause();
      setIsPlaying(false);
    }
    if (selectedTrack?.root === track.root && selectedTrack.path === track.path) {
      setSelectedTrack(null);
    }
    refreshTree();
  };

  const handleOpenFolder = async (track: Track) => {
    await openFolder(track.root, track.path);
  };

  const handleAddToQueue = useCallback((track: Track) => {
    setQueue((prev) => [...prev, track]);
  }, []);

  const handlePlayNext = useCallback((track: Track) => {
    setQueue((prev) => [track, ...prev]);
  }, []);

  const handleRemoveFromQueue = useCallback((index: number) => {
    setQueue((prev) => prev.filter((_, idx) => idx !== index));
  }, []);

  const handleClearQueue = useCallback(() => {
    setQueue([]);
  }, []);

  const nextUpTitle = queue[0]
    ? queue[0].title || queue[0].path.split("/").pop() || "Unknown track"
    : "None";

  const handleSkipNext = useCallback(() => {
    const next = queueRef.current[0];
    if (!next) {
      return;
    }
    setQueue((prev) => prev.slice(1));
    playTrack(next);
  }, [playTrack]);

  const handleSkipBack = useCallback(() => {
    const audio = audioRef.current;
    if (!nowPlayingRef.current) {
      return;
    }
    if (audio.currentTime > 2) {
      audio.currentTime = 0;
      setCurrentTime(0);
      return;
    }
    const prev = historyRef.current[historyRef.current.length - 1];
    if (!prev) {
      return;
    }
    setHistory((prevHistory) => prevHistory.slice(0, -1));
    playTrack(prev, { fromHistory: true });
  }, [playTrack]);

  const nowPlayingUrl = nowPlaying ? buildFileUrl(nowPlaying) : null;

  const handleOpenPlaylist = (name: string) => {
    setRoot("Playlists");
    setCurrentPath(name);
    setView("Playlists");
  };

  const handlePlayPlaylist = async (name: string) => {
    const entries = await fetchTree("Playlists", name);
    const tracks = entries
      .filter((entry) => entry.type === "file")
      .map((entry) => ({
        root: "Playlists" as const,
        path: entry.path,
        title: entry.title || entry.name,
        artist: entry.artist,
        thumbnail: entry.thumbnail,
        source: entry.source,
      }));
    if (tracks.length === 0) {
      return;
    }
    const [first, ...rest] = tracks;
    setQueue(rest);
    playTrack(first);
  };

  const handlePartyStart = useCallback(async () => {
    setPartyStatus("Starting party room...");
    try {
      const data = await startParty();
      const code = String(data.code || "").toUpperCase();
      const host = await resolvePartyHost();
      const url = buildPartyUrl(code, host);
      setPartyCode(code);
      setPartyUrl(url);
      setPartyActive(true);
      if (isLocalHost(window.location.hostname) && host === window.location.hostname) {
        setPartyStatus("Party room live. Open via your LAN IP for other devices.");
      } else {
        setPartyStatus("Party room live.");
      }
      partySeenRef.current = new Set();
    } catch (error) {
      setPartyStatus((error as Error).message);
    }
  }, [buildPartyUrl, resolvePartyHost]);

  const handlePartyHostSave = useCallback(
    (value: string) => {
      const normalized = normalizePartyHost(value);
      setPartyHost(normalized);
      if (normalized) {
        window.localStorage.setItem("gplay-party-host", normalized);
      } else {
        window.localStorage.removeItem("gplay-party-host");
      }
      if (partyActive && partyCode) {
        setPartyUrl(buildPartyUrl(partyCode, normalized));
      }
    },
    [buildPartyUrl, partyActive, partyCode]
  );

  const handlePartyStop = useCallback(async () => {
    setPartyStatus("Stopping party room...");
    try {
      await stopParty();
      setPartyActive(false);
      setPartyCode(null);
      setPartyUrl(null);
      setPartyStatus("Party room stopped.");
      partySeenRef.current = new Set();
    } catch (error) {
      setPartyStatus((error as Error).message);
    }
  }, []);

  useEffect(() => {
    if (!partyActive || !partyCode) {
      return;
    }
    let isActive = true;
    const poll = async () => {
      try {
        const data = await partyQueue(partyCode);
        if (!isActive) {
          return;
        }
        const items = Array.isArray(data.queue) ? data.queue : [];
        const nextTracks: Track[] = [];
        items.forEach((item: { id: string; track: Track }) => {
          if (!item?.id || !item?.track) {
            return;
          }
          if (!partySeenRef.current.has(item.id)) {
            partySeenRef.current.add(item.id);
            nextTracks.push(item.track);
          }
        });
        if (nextTracks.length) {
          setQueue((prev) => [...prev, ...nextTracks]);
        }
      } catch (error) {
        if (isActive) {
          const err = error as Error & { status?: number };
          if (err.status === 403) {
            setPartyActive(false);
            setPartyCode(null);
            setPartyUrl(null);
            setPartyStatus("Party room expired. Start a new room.");
            return;
          }
          setPartyStatus(err.message);
        }
      }
    };
    poll();
    const id = window.setInterval(poll, 3000);
    return () => {
      isActive = false;
      window.clearInterval(id);
    };
  }, [partyActive, partyCode]);

  const viewContent = useMemo(() => {
    const genreMap: Record<string, VisualizerMode> = {
      Electronic: "Electronic",
      "Beach/Tropical": "Beachy/Tropical",
      Psychedelic: "Trippy/Psychedelic",
      Sleepy: "Sleepy",
      Classical: "Sleepy",
      Wakeful: "Wakeful",
      Rock: "Wakeful",
      "Hip-Hop": "Wakeful",
      Chill: "Chill",
      Jazz: "Chill",
      RnB: "Chill",
      Acoustic: "Chill",
      Pop: "Chill",
      Other: "Trippy/Psychedelic",
    };
    const modeFromGenre = (value: string): VisualizerMode =>
      genreMap[value] || "Chill";

    const activeMode = visualizerAuto ? modeFromGenre(genre) : visualizerMode;
    switch (view) {
      case "NowPlaying":
        return (
          <NowPlayingView
            track={nowPlaying}
            isPlaying={isPlaying}
            onTogglePlay={togglePlay}
            onOpenVisualizer={() => setView("Visualizer")}
            onOpenParty={() => setView("Party")}
            onOpenTune={() => {
              if (nowPlaying) {
                setSelectedTrack(nowPlaying);
              }
              setView("Tuning");
            }}
            onRename={handleRenameTrack}
            onSaveToLibrary={handleSaveToLibrary}
            onDeleteTrack={handleDeleteTrack}
            queue={queue}
            onQueueRemove={handleRemoveFromQueue}
            onQueueClear={handleClearQueue}
            partyActive={partyActive}
            partyCode={partyCode}
            partyUrl={partyUrl}
            partyStatus={partyStatus}
            onPartyStart={handlePartyStart}
            onPartyStop={handlePartyStop}
            playlists={playlists}
            onAddToPlaylist={handleAddToPlaylist}
            playlistContents={playlistContents}
            genre={genre}
            onGenreChange={setGenre}
            visualizerAuto={visualizerAuto}
            onVisualizerAutoChange={setVisualizerAuto}
            visualizerMode={activeMode}
            onVisualizerModeChange={setVisualizerMode}
            useArtworkColors={useArtworkColors}
            onUseArtworkColorsChange={setUseArtworkColors}
            currentTime={currentTime}
            duration={duration}
            onSeek={(time) => {
              const audio = audioRef.current;
              audio.currentTime = time;
              setCurrentTime(time);
            }}
            audioUrl={nowPlayingUrl}
          />
        );
      case "Download":
        return (
          <DownloadView
            playlists={playlists}
            onTrackDownloaded={handleTrackDownloaded}
            onUploadComplete={refreshTree}
          />
        );
      case "Tuning":
        return (
          <TuningView
            selectedTrack={selectedTrack}
            onTuneComplete={handleTuneComplete}
          />
        );
      case "Visualizer":
        return (
          <VisualizerView
            track={nowPlaying}
            isPlaying={isPlaying}
            ensureAnalyser={ensureAnalyser}
            mode={activeMode}
            genre={genre}
            visualizerAuto={visualizerAuto}
            onVisualizerAutoChange={setVisualizerAuto}
            onGenreChange={setGenre}
            onModeChange={setVisualizerMode}
            useArtworkColors={useArtworkColors}
            onUseArtworkColorsChange={setUseArtworkColors}
          />
        );
      case "Playlists":
        return (
          <PlaylistsView
            playlists={playlists}
            onCreate={() => setView("CreatePlaylist")}
            onOpenPlaylist={handleOpenPlaylist}
            onPlayPlaylist={handlePlayPlaylist}
            libraryTracks={libraryTracks}
            onAddTrack={handleAddToPlaylist}
            playlistContents={playlistContents}
            onRefresh={refreshTree}
          />
        );
      case "CreatePlaylist":
        return (
          <CreatePlaylistView
            onSubmit={handleCreatePlaylist}
            onCancel={() => setView("Playlists")}
            libraryTracks={libraryTracks}
            onAddTrack={handleAddToPlaylist}
          />
        );
      case "Party":
        return (
          <PartyRoomView
            partyActive={partyActive}
            partyCode={partyCode}
            partyUrl={partyUrl}
            partyStatus={partyStatus}
            onPartyStart={handlePartyStart}
            onPartyStop={handlePartyStop}
            partyHost={partyHost}
            onPartyHostSave={handlePartyHostSave}
            queue={queue}
          />
        );
      case "Home":
      default:
        return <HomeView />;
    }
  }, [
    view,
    playlists,
    libraryTracks,
    playlistContents,
    selectedTrack,
    nowPlaying,
    isPlaying,
    handleTrackDownloaded,
    handleTuneComplete,
    ensureAnalyser,
    visualizerAuto,
    visualizerMode,
    genre,
    useArtworkColors,
    togglePlay,
    handlePlayPlaylist,
    handleSaveToLibrary,
    handleRemoveFromQueue,
    handleClearQueue,
    queue,
    partyActive,
    partyCode,
    partyUrl,
    partyStatus,
    handlePartyStart,
    handlePartyStop,
    partyHost,
    handlePartyHostSave,
    currentTime,
    duration,
  ]);

  if (partyGuest) {
    return <PartyGuestView />;
  }

  return (
    <div className="app-shell">
      <Sidebar
        view={view}
        onNavigate={setView}
        root={root}
        onRootChange={handleRootChange}
        currentPath={currentPath}
        onPathChange={setCurrentPath}
        refreshToken={refreshToken}
        librarySort={librarySort}
        onLibrarySortChange={setLibrarySort}
        onSelectTrack={setSelectedTrack}
        onPlayTrack={playTrack}
        onSaveToLibrary={handleSaveToLibrary}
        onDeleteTrack={handleDeleteTrack}
        onOpenFolder={handleOpenFolder}
        onAddToQueue={handleAddToQueue}
        onPlayNext={handlePlayNext}
      />
      <main className="main">
        {view !== "NowPlaying" ? (
          <NowPlaying
            track={nowPlaying}
            isPlaying={isPlaying}
            expanded={nowExpanded}
            onTogglePlay={togglePlay}
            onSkipBack={handleSkipBack}
            onSkipNext={handleSkipNext}
            onToggleExpanded={() => setNowExpanded((prev) => !prev)}
            onOpenNowPlaying={() => setView("NowPlaying")}
            onOpenParty={() => setView("Party")}
            onOpenVisualizer={() => setView("Visualizer")}
            onOpenTune={() => {
              if (nowPlaying) {
                setSelectedTrack(nowPlaying);
              }
              setView("Tuning");
            }}
            onRename={handleRenameTrack}
            onSaveToLibrary={handleSaveToLibrary}
            onDeleteTrack={handleDeleteTrack}
            queue={queue}
            onQueueRemove={handleRemoveFromQueue}
            onQueueClear={handleClearQueue}
            partyActive={partyActive}
            partyCode={partyCode}
            partyUrl={partyUrl}
            partyStatus={partyStatus}
            onPartyStart={handlePartyStart}
            onPartyStop={handlePartyStop}
            playlists={playlists}
            onAddToPlaylist={handleAddToPlaylist}
            playlistContents={playlistContents}
            currentTime={currentTime}
            duration={duration}
            onSeek={(time) => {
              const audio = audioRef.current;
              audio.currentTime = time;
              setCurrentTime(time);
            }}
            audioUrl={nowPlayingUrl}
            upNextTitle={nextUpTitle}
          />
        ) : null}
        <div className="content">{viewContent}</div>
      </main>
    </div>
  );
};

export default App;
