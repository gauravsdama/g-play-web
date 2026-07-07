import { useEffect, useState } from "react";
import { Track } from "../types";

type PartyRoomViewProps = {
  partyActive: boolean;
  partyCode: string | null;
  partyUrl: string | null;
  partyStatus: string | null;
  partyHost: string;
  onPartyHostSave: (host: string) => void;
  onPartyStart: () => void;
  onPartyStop: () => void;
  queue: Track[];
};

const PartyRoomView = ({
  partyActive,
  partyCode,
  partyUrl,
  partyStatus,
  partyHost,
  onPartyHostSave,
  onPartyStart,
  onPartyStop,
  queue,
}: PartyRoomViewProps) => {
  const [hostValue, setHostValue] = useState(partyHost);
  const [platform, setPlatform] = useState("mac");
  const [copyStatus, setCopyStatus] = useState<string | null>(null);

  const commandMap: Record<string, string> = {
    mac: "ipconfig getifaddr en0",
    windows: "ipconfig",
  };

  useEffect(() => {
    setHostValue(partyHost);
  }, [partyHost]);

  const handleSaveHost = () => {
    onPartyHostSave(hostValue);
  };

  const handleCopyCommand = async () => {
    const command = commandMap[platform] || commandMap.mac;
    try {
      await navigator.clipboard.writeText(command);
      setCopyStatus("Copied.");
    } catch {
      setCopyStatus("Copy failed.");
    }
  };

  return (
    <div className="view party-room-view">
      <div className="party-card">
        <div className="party-header">
          <div>
            <p className="muted">Party Room</p>
            <h2>{partyActive ? `Room ${partyCode}` : "Party mode off"}</h2>
            <p className="muted">
              Friends can scan the QR code or open the link to add YouTube tracks to your queue.
            </p>
          </div>
          {partyActive ? (
            <button className="btn ghost" onClick={onPartyStop}>
              Stop
            </button>
          ) : (
            <button className="btn primary" onClick={onPartyStart}>
              Start Party Room
            </button>
          )}
        </div>
        {partyActive && partyUrl ? (
          <div className="party-body">
            <div className="party-qr">
              <img
                src={`https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=${encodeURIComponent(
                  partyUrl
                )}`}
                alt="Party QR"
              />
            </div>
            <div className="party-link">
              <p className="muted">Share link</p>
              <code>{partyUrl}</code>
              <p className="muted">Queue size: {queue.length}</p>
            </div>
          </div>
        ) : (
          <p className="muted">Start Party Mode to enable guest submissions.</p>
        )}
        <div className="party-host">
          <p className="muted">LAN address for QR</p>
          <div className="party-host-input">
            <input
              type="text"
              value={hostValue}
              onChange={(event) => setHostValue(event.target.value)}
              placeholder="192.168.1.10"
            />
            <button className="btn ghost" onClick={handleSaveHost}>
              Use
            </button>
          </div>
          <p className="muted">
            If the link shows localhost, paste your LAN IP (optional :port).
          </p>
          <div className="party-ip-tools">
            <div className="party-ip-header">
              <p className="muted">Find your IP address</p>
              <select value={platform} onChange={(event) => setPlatform(event.target.value)}>
                <option value="mac">macOS</option>
                <option value="windows">Windows</option>
              </select>
            </div>
            <div className="party-ip-command">
              <code>{commandMap[platform] || commandMap.mac}</code>
              <button className="btn ghost" onClick={handleCopyCommand}>
                Copy
              </button>
            </div>
            {copyStatus ? <p className="muted">{copyStatus}</p> : null}
          </div>
        </div>
        {partyStatus ? <p className="status">{partyStatus}</p> : null}
      </div>
    </div>
  );
};

export default PartyRoomView;
