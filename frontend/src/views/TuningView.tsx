import { useEffect, useMemo, useState } from "react";
import { applyCuts, buildFileUrl, deleteTrack, fetchTrackMeta, tuneTrack } from "../api";
import MiniPlayer from "../components/MiniPlayer";
import WaveformTimeline, { CutRange } from "../components/WaveformTimeline";
import { Track } from "../types";
import { CUSTOM_PRESET, EQ_BANDS, PRESETS } from "../tuningPresets";

type TuningViewProps = {
  selectedTrack: Track | null;
  onTuneComplete: (track: Track) => void;
};

const TuningView = ({ selectedTrack, onTuneComplete }: TuningViewProps) => {
  const [presetName, setPresetName] = useState("Flat");
  const [eqGains, setEqGains] = useState<number[]>(PRESETS.Flat.eq);
  const [preamp, setPreamp] = useState(0);
  const [spatialWidth, setSpatialWidth] = useState(0);
  const [drcMode, setDrcMode] = useState("Off");
  const [balance, setBalance] = useState(0);
  const [limiterOn, setLimiterOn] = useState(true);
  const [status, setStatus] = useState<string | null>(null);
  const [editStatus, setEditStatus] = useState<string | null>(null);
  const [tunedTrack, setTunedTrack] = useState<Track | null>(null);
  const [cuts, setCuts] = useState<CutRange[]>([]);

  const presetOptions = useMemo(() => [CUSTOM_PRESET, ...Object.keys(PRESETS)], []);

  const applyPreset = (name: string) => {
    if (name === CUSTOM_PRESET) {
      setPresetName(CUSTOM_PRESET);
      return;
    }
    const preset = PRESETS[name];
    if (!preset) {
      return;
    }
    setPresetName(name);
    setEqGains([...preset.eq]);
    setSpatialWidth(preset.spatial);
    setDrcMode(preset.drc);
    setPreamp(preset.preamp ?? 0);
  };

  const updateEq = (index: number, value: number) => {
    setPresetName((prev) => (prev === CUSTOM_PRESET ? prev : CUSTOM_PRESET));
    setEqGains((prev) => prev.map((gain, idx) => (idx === index ? value : gain)));
  };

  useEffect(() => {
    let cancelled = false;
    const resetToFlat = () => {
      setPresetName("Flat");
      setEqGains([...PRESETS.Flat.eq]);
      setSpatialWidth(PRESETS.Flat.spatial);
      setDrcMode(PRESETS.Flat.drc);
      setPreamp(PRESETS.Flat.preamp ?? 0);
      setBalance(0);
      setLimiterOn(true);
    };

    if (!selectedTrack) {
      resetToFlat();
      setCuts([]);
      return () => {
        cancelled = true;
      };
    }

    const loadMeta = async () => {
      try {
        const data = await fetchTrackMeta(selectedTrack.root, selectedTrack.path);
        if (cancelled) {
          return;
        }
        const tuning = data?.meta?.tuning;
        if (tuning && typeof tuning === "object") {
          const eq = Array.isArray(tuning.eq_gains) ? tuning.eq_gains : [];
          const normalizedEq = EQ_BANDS.map((_, idx) => Number(eq[idx] ?? 0));
          setEqGains(normalizedEq);
          setPreamp(Number(tuning.preamp_db ?? 0));
          setSpatialWidth(Math.round(Number(tuning.spatial_width ?? 0) * 100));
          setDrcMode(String(tuning.drc_mode ?? "Off"));
          setBalance(Number(tuning.balance ?? 0));
          setLimiterOn(tuning.limiter_on ?? true);
          const storedPreset =
            typeof tuning.preset_name === "string" && PRESETS[tuning.preset_name]
              ? tuning.preset_name
              : CUSTOM_PRESET;
          setPresetName(storedPreset);
        } else {
          resetToFlat();
        }
      } catch {
        if (!cancelled) {
          resetToFlat();
        }
      }
    };

    loadMeta();
    return () => {
      cancelled = true;
    };
  }, [selectedTrack]);

  const handleTune = async () => {
    if (!selectedTrack) {
      setStatus("Select a track from the Explorer first.");
      return;
    }
    setStatus("Rendering tuned track...");
    try {
      const payload = {
        root: selectedTrack.root,
        path: selectedTrack.path,
        preamp_db: preamp,
        eq_gains: eqGains,
        spatial_width: spatialWidth / 100,
        drc_mode: drcMode,
        balance,
        limiter_on: limiterOn,
        preset_name: presetName,
      };
      const data = await tuneTrack(payload);
      const track: Track = {
        root: "Edited",
        path: data.path,
        title: data.title,
        artist: data.artist,
        thumbnail: data.thumbnail,
      };
      setTunedTrack(track);
      onTuneComplete(track);
      setStatus("Tune complete. New file saved in Edited.");
    } catch (error) {
      setStatus((error as Error).message);
    }
  };

  const originalUrl = selectedTrack ? buildFileUrl(selectedTrack) : null;
  const tunedUrl = tunedTrack ? buildFileUrl(tunedTrack) : null;

  const handleApplyCuts = async () => {
    if (!selectedTrack) {
      setEditStatus("Select a track to edit.");
      return;
    }
    if (cuts.length === 0) {
      setEditStatus("Add a cut region on the waveform first.");
      return;
    }
    setEditStatus("Rendering edit...");
    try {
      const data = await applyCuts(selectedTrack.root, selectedTrack.path, cuts);
      const track: Track = {
        root: "Edited",
        path: data.path,
        title: data.title,
        artist: data.artist,
        thumbnail: data.thumbnail,
      };
      setTunedTrack(track);
      onTuneComplete(track);
      setCuts([]);
      setEditStatus("Edit complete. Saved to Edited.");
    } catch (error) {
      setEditStatus((error as Error).message);
    }
  };

  const handleDeleteEdited = async () => {
    if (!tunedTrack) {
      return;
    }
    setEditStatus("Deleting edited file...");
    try {
      await deleteTrack(tunedTrack.root, tunedTrack.path);
      setTunedTrack(null);
      setEditStatus("Deleted.");
    } catch (error) {
      setEditStatus((error as Error).message);
    }
  };

  return (
    <div className="view">
      <div className="panel">
        <h2>Audio Tuning</h2>
        <p className="muted">
          Start from a preset, then fine-tune every band. Rendered files save into Edited for A/B
          playback.
        </p>
        <div className="field">
          <label>Preset</label>
          <select
            value={presetName}
            onChange={(event) => applyPreset(event.target.value)}
          >
            {presetOptions.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </div>
        <div className="eq-grid">
          {EQ_BANDS.map((band, index) => (
            <div key={band} className="eq-band">
              <label>{band >= 1000 ? `${band / 1000}k` : band}Hz</label>
              <input
                type="range"
                min={-12}
                max={12}
                step={0.5}
                value={eqGains[index]}
                onChange={(event) => updateEq(index, Number(event.target.value))}
              />
              <span>{eqGains[index].toFixed(1)} dB</span>
            </div>
          ))}
        </div>
        <div className="grid-2">
          <div className="field">
            <label>Preamp</label>
            <input
              type="range"
              min={-12}
              max={12}
              step={0.5}
              value={preamp}
              onChange={(event) => {
                setPresetName((prev) => (prev === CUSTOM_PRESET ? prev : CUSTOM_PRESET));
                setPreamp(Number(event.target.value));
              }}
            />
            <span>{preamp.toFixed(1)} dB</span>
          </div>
          <div className="field">
            <label>Spatial Width</label>
            <input
              type="range"
              min={0}
              max={100}
              step={1}
              value={spatialWidth}
              onChange={(event) => {
                setPresetName((prev) => (prev === CUSTOM_PRESET ? prev : CUSTOM_PRESET));
                setSpatialWidth(Number(event.target.value));
              }}
            />
            <span>{spatialWidth}%</span>
          </div>
          <div className="field">
            <label>Dynamic Range</label>
            <select
              value={drcMode}
              onChange={(event) => {
                setPresetName((prev) => (prev === CUSTOM_PRESET ? prev : CUSTOM_PRESET));
                setDrcMode(event.target.value);
              }}
            >
              <option value="Off">Off</option>
              <option value="Medium">Medium</option>
              <option value="High">High</option>
            </select>
          </div>
          <div className="field">
            <label>Balance</label>
            <input
              type="range"
              min={-1}
              max={1}
              step={0.01}
              value={balance}
              onChange={(event) => {
                setPresetName((prev) => (prev === CUSTOM_PRESET ? prev : CUSTOM_PRESET));
                setBalance(Number(event.target.value));
              }}
            />
            <span>{balance.toFixed(2)}</span>
          </div>
          <div className="field checkbox">
            <label>Limiter</label>
            <input
              type="checkbox"
              checked={limiterOn}
              onChange={(event) => {
                setPresetName((prev) => (prev === CUSTOM_PRESET ? prev : CUSTOM_PRESET));
                setLimiterOn(event.target.checked);
              }}
            />
          </div>
        </div>
        <button className="btn primary" onClick={handleTune}>
          Render Edited Track
        </button>
        {status ? <p className="status">{status}</p> : null}
      </div>
      <div className="panel">
        <h3>Playback Compare</h3>
        <div className="compare-grid">
          <div>
            <p className="muted">Original</p>
            {originalUrl ? (
              <MiniPlayer label="Original" src={originalUrl} />
            ) : (
              <p className="muted">Select a track to preview.</p>
            )}
          </div>
          <div>
            <p className="muted">Edited</p>
            {tunedUrl ? (
              <>
                <MiniPlayer label="Edited" src={tunedUrl} />
                <button className="btn ghost" onClick={handleDeleteEdited}>
                  Delete Edited File
                </button>
              </>
            ) : (
              <p className="muted">No edit yet.</p>
            )}
          </div>
        </div>
      </div>
      <div className="panel">
        <h3>Trim & Crop</h3>
        <p className="muted">
          Drag across the waveform to mark sections you want to remove. Scroll and zoom to
          fine-tune the cuts.
        </p>
        <WaveformTimeline
          audioUrl={originalUrl}
          height={70}
          editable
          cuts={cuts}
          onCutsChange={setCuts}
        />
        <button className="btn primary" onClick={handleApplyCuts} disabled={!originalUrl}>
          Apply Cuts
        </button>
        {editStatus ? <p className="status">{editStatus}</p> : null}
      </div>
    </div>
  );
};

export default TuningView;
