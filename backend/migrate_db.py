"""
Script de migração para criar novas tabelas no banco de dados.
Execute este script uma vez após atualizar o backend:

    docker exec -it orfeu_backend python migrate_db.py

Ou rode diretamente se estiver no container.
"""

from app.database import engine, Base
from app import models

def run_migration():
    print("🔄 Iniciando migração do banco de dados...")
    
    # Cria todas as tabelas que não existem
    # Tabelas existentes NÃO são alteradas (seguro)
    Base.metadata.create_all(bind=engine)
    
    print("✅ Migração concluída!")
    print("")
    print("Novas tabelas/colunas criadas (se não existiam):")
    print("  - downloaded_tracks: Mapeia tidal_id/ytmusic_id para arquivos locais")
    print("  - tracks.tidal_id: Link direto para ID do Tidal")
    print("  - tracks.genre: Gênero musical")

if __name__ == "__main__":
    run_migration()
