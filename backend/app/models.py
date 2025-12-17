from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, DateTime, Float, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    email = Column(String, unique=True, index=True)
    full_name = Column(String)
    hashed_password = Column(String)
    is_active = Column(Boolean, default=True)
    profile_image_url = Column(Text, nullable=True)  # URL ou base64 da imagem de perfil
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    history = relationship("ListenHistory", back_populates="user")
    playlists = relationship("Playlist", back_populates="owner")
    favorites = relationship("Favorite", back_populates="user")

class Track(Base):
    __tablename__ = "tracks"

    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String, unique=True, index=True)
    title = Column(String, index=True)
    artist = Column(String, index=True)
    album = Column(String, index=True)
    duration = Column(Float)
    genre = Column(String, nullable=True)
    tidal_id = Column(Integer, nullable=True, index=True)  # Link para ID do Tidal
    
    bitrate = Column(Integer, nullable=True)
    format = Column(String, nullable=True)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class DownloadedTrack(Base):
    """
    Tabela para mapear IDs de serviços externos (Tidal, YTMusic) para arquivos locais.
    Resolve o problema de músicas diferentes com mesmo nome serem mapeadas para o mesmo arquivo.
    """
    __tablename__ = "downloaded_tracks"

    id = Column(Integer, primary_key=True, index=True)
    # Identificadores externos (pelo menos um deve estar preenchido)
    tidal_id = Column(Integer, nullable=True, unique=True, index=True)
    ytmusic_id = Column(String, nullable=True, unique=True, index=True)
    
    # Metadados para fallback e display
    title = Column(String, index=True)
    artist = Column(String, index=True)
    album = Column(String, nullable=True)
    
    # Caminho do arquivo local (relativo a /downloads)
    local_path = Column(String, unique=True, index=True)
    
    # Metadados técnicos
    source = Column(String)  # 'Tidal', 'Soulseek', 'YTMusic'
    file_hash = Column(String, nullable=True)  # SHA256 do arquivo para integridade
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class ListenHistory(Base):
    __tablename__ = "listen_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    track_id = Column(Integer, ForeignKey("tracks.id"))
    played_at = Column(DateTime(timezone=True), server_default=func.now())
    duration_listened = Column(Float)

    user = relationship("User", back_populates="history")
    track = relationship("Track")

class Favorite(Base):
    __tablename__ = "favorites"
    
    user_id = Column(Integer, ForeignKey("users.id"), primary_key=True)
    track_id = Column(Integer, ForeignKey("tracks.id"), primary_key=True)
    added_at = Column(DateTime(timezone=True), server_default=func.now())
    
    user = relationship("User", back_populates="favorites")
    track = relationship("Track")

class Playlist(Base):
    __tablename__ = "playlists"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    name = Column(String)
    is_public = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    owner = relationship("User", back_populates="playlists")
    items = relationship("PlaylistItem", back_populates="playlist")

class PlaylistItem(Base):
    __tablename__ = "playlist_items"

    id = Column(Integer, primary_key=True, index=True)
    playlist_id = Column(Integer, ForeignKey("playlists.id"))
    track_id = Column(Integer, ForeignKey("tracks.id"))
    order = Column(Integer)

    playlist = relationship("Playlist", back_populates="items")
    track = relationship("Track")

class SavedAlbum(Base):
    """Álbuns salvos na biblioteca do usuário"""
    __tablename__ = "saved_albums"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    album_id = Column(String, index=True)  # Tidal ID ou YTMusic ID
    title = Column(String)
    artist = Column(String)
    artwork_url = Column(Text)
    year = Column(String, nullable=True)
    is_pinned = Column(Boolean, default=False)
    added_at = Column(DateTime(timezone=True), server_default=func.now())

class SavedArtist(Base):
    """Artistas salvos na biblioteca do usuário"""
    __tablename__ = "saved_artists"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    artist_id = Column(String, index=True)  # Tidal ID ou YTMusic ID
    name = Column(String)
    image_url = Column(Text)
    is_pinned = Column(Boolean, default=False)
    added_at = Column(DateTime(timezone=True), server_default=func.now())