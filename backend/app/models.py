from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, DateTime, Float
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
    
    bitrate = Column(Integer, nullable=True)
    format = Column(String, nullable=True)
    
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