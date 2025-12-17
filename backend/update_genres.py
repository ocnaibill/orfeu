#!/usr/bin/env python3
"""
Script para extrair e atualizar gêneros das tracks a partir da API do iTunes.
"""
import os
import sys
import time

# Adiciona o diretório app ao path
sys.path.insert(0, '/app')

from app.database import SessionLocal
from app import models
from app.services.metadata_provider import MetadataProvider

def update_genres():
    """Atualiza os gêneros de todas as tracks no banco de dados usando a API do iTunes."""
    db = SessionLocal()
    
    try:
        # Busca tracks sem gênero ou com gênero vazio/desconhecido
        tracks = db.query(models.Track).filter(
            (models.Track.genre.is_(None)) | 
            (models.Track.genre == '') |
            (models.Track.genre == 'Desconhecido')
        ).all()
        
        print(f"📊 Encontradas {len(tracks)} tracks sem gênero definido")
        
        updated = 0
        not_found = 0
        
        for i, track in enumerate(tracks):
            artist = track.artist or ""
            album = track.album or ""
            title = track.title or ""
            
            print(f"[{i+1}/{len(tracks)}] Buscando gênero para: {artist} - {title}...", end=" ")
            
            genre = MetadataProvider.get_genre(artist, album, title)
            
            if genre and genre != "Desconhecido":
                track.genre = genre
                updated += 1
                print(f"✅ {genre}")
            else:
                not_found += 1
                print(f"❌ Não encontrado")
            
            # Pequeno delay para não sobrecarregar a API do iTunes
            time.sleep(0.3)
        
        db.commit()
        
        print(f"\n📈 Resumo:")
        print(f"  - Atualizadas: {updated}")
        print(f"  - Não encontradas: {not_found}")
        
        # Mostra distribuição de gêneros após atualização
        from sqlalchemy import func
        genres = db.query(
            models.Track.genre, 
            func.count(models.Track.id).label('count')
        ).filter(
            models.Track.genre.isnot(None), 
            models.Track.genre != '',
            models.Track.genre != 'Desconhecido'
        ).group_by(models.Track.genre).all()
        
        if genres:
            print(f"\n🎵 Distribuição de gêneros:")
            for genre, count in sorted(genres, key=lambda x: -x[1]):
                print(f"  - {genre}: {count}")
        
    finally:
        db.close()


if __name__ == "__main__":
    print("🎵 Atualizando gêneros das tracks via iTunes API...\n")
    update_genres()
