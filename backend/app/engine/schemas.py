from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field


class DownloadRequest(BaseModel):
    url: str
    playlist: Optional[str] = None
    quality_kbps: int = 320


class TuneRequest(BaseModel):
    root: str
    path: str
    preamp_db: float = 0.0
    eq_gains: List[float] = Field(default_factory=list)
    spatial_width: float = 0.0
    drc_mode: str = "Off"
    balance: float = 0.0
    limiter_on: bool = True
    preset_name: Optional[str] = None
    output_name: Optional[str] = None


class PlaylistCreateRequest(BaseModel):
    name: str


class PlaylistAddRequest(BaseModel):
    playlist: str
    root: str
    path: str


class RenameRequest(BaseModel):
    root: str
    path: str
    new_name: str


class SaveToLibraryRequest(BaseModel):
    root: str
    path: str


class DeleteRequest(BaseModel):
    root: str
    path: str


class OpenFolderRequest(BaseModel):
    root: str
    path: Optional[str] = None


class InfoRequest(BaseModel):
    url: str


class AudioProfileRequest(BaseModel):
    root: str
    path: str
    min_coverage: float = 0.02


class TrackMetaRequest(BaseModel):
    root: str
    path: str


class CutRange(BaseModel):
    start: float
    end: float


class EditCutsRequest(BaseModel):
    root: str
    path: str
    cuts: List[CutRange]
    output_name: Optional[str] = None


class PartyEnqueueRequest(BaseModel):
    code: str
    url: str
    quality_kbps: int = 320


class PartyQueueRequest(BaseModel):
    code: str
