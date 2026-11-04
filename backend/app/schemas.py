from pydantic import BaseModel
from typing import Optional


class UserCreate(BaseModel):
    username: str
    email: str
    password: str
    full_name: str

class Token(BaseModel):
    access_token: str
    token_type: str

class DownloadRequest(BaseModel):
    username: str
    filename: str
    size: Optional[int] = None

class AutoDownloadRequest(BaseModel):
    search_id: str

class SmartDownloadRequest(BaseModel):
    artist: str
    track: str
    album: Optional[str] = None
    tidalId: Optional[int] = None
    artworkUrl: Optional[str] = None

class FavoriteRequest(BaseModel):
    filename: str
    title: str
    artist: str
    album: Optional[str] = None

class HistoryRequest(BaseModel):
    filename: str
    duration_listened: float
    album_id: Optional[str] = None  # ID do álbum no catálogo (Tidal/YTMusic)
    genre: Optional[str] = None  # Gênero do álbum
    # Metadados do catálogo (mais confiáveis que tags do arquivo)
    catalog_title: Optional[str] = None
    catalog_artist: Optional[str] = None
    catalog_album: Optional[str] = None

class PlaylistCreate(BaseModel):
    name: str
    is_public: bool = False

class PlaylistItemAdd(BaseModel):
    filename: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None

class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None  # URL da imagem
    current_password: Optional[str] = None  # Senha atual (para verificação)
    new_password: Optional[str] = None  # Nova senha

class ProfileImageUpload(BaseModel):
    image_data: str  # Base64 da imagem (pode ser PNG, JPG, GIF, WebP)
    content_type: str = "image/png"  # Tipo MIME da imagem

class LastfmAuthRequest(BaseModel):
    username: str
    password: str

class LastfmScrobbleRequest(BaseModel):
    artist: str
    track: str
    album: Optional[str] = None
    timestamp: Optional[int] = None
    duration: Optional[int] = None

class SaveAlbumRequest(BaseModel):
    album_id: str
    title: str
    artist: str
    artwork_url: Optional[str] = None
    year: Optional[int] = None

class SaveArtistRequest(BaseModel):
    artist_id: str
    name: str
    image_url: Optional[str] = None

class PlaylistUpdateRequest(BaseModel):
    name: Optional[str] = None
    cover_url: Optional[str] = None
    is_public: Optional[bool] = None

class UpdateAlbumGenreRequest(BaseModel):
    album_id: str
    genre: str
