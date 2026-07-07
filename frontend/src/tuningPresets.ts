export const EQ_BANDS = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

export const CUSTOM_PRESET = "Custom";

export type EqPreset = { eq: number[]; spatial: number; drc: string; preamp?: number };

export const PRESETS: Record<string, EqPreset> = {
  Flat: { eq: Array(10).fill(0), spatial: 0, drc: "Off" },
  "High-End Spatial Audio": { eq: [3, 3, 2, -1, -1, 0, 1, 2, 3, 3], spatial: 45, drc: "Off" },
  "Late Night": { eq: Array(10).fill(0), spatial: 0, drc: "High" },
  Acoustic: { eq: [2, 2, 1, 0, 0, 1, 2, 2, 2, 1], spatial: 0, drc: "Off" },
  "Bass Booster": { eq: [5, 4, 3, 2, 1, 0, -1, -2, -2, -2], spatial: 0, drc: "Off" },
  "Bass Reducer": { eq: [-4, -4, -3, -2, -1, 0, 0, 0, 0, 0], spatial: 0, drc: "Off" },
  Classical: { eq: [3, 2, 1, -1, -2, -1, 1, 2, 3, 3], spatial: 10, drc: "Off" },
  Dance: { eq: [5, 4, 3, 1, 0, 1, 2, 3, 3, 2], spatial: 10, drc: "Off" },
  Deep: { eq: [3, 2, 2, 1, 0, 0, -1, -2, -2, -3], spatial: 0, drc: "Off" },
  Electronic: { eq: [5, 4, 3, 0, -2, -2, -1, 0, 1, 2], spatial: 10, drc: "Off" },
  "Hip-Hop": { eq: [4, 4, 3, 2, 1, 0, -1, 0, 2, 2], spatial: 0, drc: "Off" },
  Jazz: { eq: [3, 2, 1, -1, -2, -1, 1, 2, 2, 3], spatial: 10, drc: "Off" },
  Latin: { eq: [4, 3, 2, -1, -2, -1, 1, 2, 3, 4], spatial: 10, drc: "Off" },
  Loudness: { eq: [4, 3, 2, -1, -2, -2, -1, 0, 2, 2], spatial: 0, drc: "Off" },
  Lounge: { eq: [-2, -2, -1, 1, 2, 2, 1, 0, -1, -2], spatial: 0, drc: "Off" },
  Piano: { eq: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], spatial: 0, drc: "Off" },
  Pop: { eq: [-1, -1, 0, 1, 2, 2, 1, 0, -1, -1], spatial: 0, drc: "Off" },
  "R&B": { eq: [5, 4, 3, 0, -2, -2, -1, 0, 1, 2], spatial: 0, drc: "Off" },
  Rock: { eq: [4, 3, 2, 0, -1, -1, 0, 2, 3, 3], spatial: 0, drc: "Off" },
  "Small Speakers": { eq: [3, 3, 2, 1, 0, -1, -2, -3, -3, -3], spatial: 0, drc: "Off" },
  "Spoken Word": { eq: [-4, -3, -2, 1, 3, 3, 2, 1, 0, 0], spatial: 0, drc: "Off" },
  "Treble Booster": { eq: [0, 0, 0, 0, 0, 1, 2, 3, 4, 4], spatial: 0, drc: "Off" },
  "Treble Reducer": { eq: [0, 0, 0, 0, 0, -1, -2, -3, -4, -4], spatial: 0, drc: "Off" },
  "Vocal Booster": { eq: [-1, -1, 0, 2, 3, 3, 2, 1, 0, -1], spatial: 0, drc: "Off" },
};
