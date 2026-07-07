import { useMemo, useState } from "react";
import { partyEnqueue } from "../api";

const PartyGuestView = () => {
  const params = useMemo(() => new URLSearchParams(window.location.search), []);
  const code = (params.get("code") || "").toUpperCase();
  const [url, setUrl] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const handleSubmit = async () => {
    if (!code) {
      setStatus("Missing party code.");
      return;
    }
    if (!url.trim()) {
      setStatus("Paste a YouTube link first.");
      return;
    }
    setPending(true);
    setStatus("Adding to queue...");
    try {
      await partyEnqueue(code, url.trim(), 320);
      setStatus("Added! Your song is in the queue.");
      setUrl("");
    } catch (error) {
      setStatus((error as Error).message);
    } finally {
      setPending(false);
    }
  };

  return (
    <div className="party-guest">
      <div className="party-card">
        <h2>G Play Party Room</h2>
        <p className="muted">
          Paste a YouTube link and we’ll add it to the host queue.
        </p>
        <div className="party-code">Room code: {code || "Unknown"}</div>
        <div className="party-input">
          <input
            type="text"
            placeholder="https://www.youtube.com/watch?v=..."
            value={url}
            onChange={(event) => setUrl(event.target.value)}
          />
          <button className="btn primary" onClick={handleSubmit} disabled={pending}>
            Add to Queue
          </button>
        </div>
        {status ? <p className="status">{status}</p> : null}
      </div>
    </div>
  );
};

export default PartyGuestView;
