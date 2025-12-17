"""
Script de migração para criar novas tabelas no banco de dados.
Execute este script uma vez após atualizar o backend:

    docker exec -it orfeu_backend python migrate_db.py

Ou rode diretamente se estiver no container.
"""

from app.database import engine, Base, SessionLocal
from app import models
from sqlalchemy import text

def run_migration():
    print("🔄 Iniciando migração do banco de dados...")
    
    db = SessionLocal()
    
    try:
        # 1. Adiciona colunas faltantes na tabela tracks
        migrations = [
            ("tracks", "tidal_id", "ALTER TABLE tracks ADD COLUMN tidal_id VARCHAR(100)"),
            ("tracks", "genre", "ALTER TABLE tracks ADD COLUMN genre VARCHAR(100)"),
            ("tracks", "album_id", "ALTER TABLE tracks ADD COLUMN album_id VARCHAR(100)"),
            ("users", "profile_image_url", "ALTER TABLE users ADD COLUMN profile_image_url TEXT"),
            ("playlists", "cover_url", "ALTER TABLE playlists ADD COLUMN cover_url TEXT"),
        ]
        
        for table, column, sql in migrations:
            try:
                # Verifica se a coluna já existe
                check_sql = text(f"""
                    SELECT column_name FROM information_schema.columns 
                    WHERE table_name = '{table}' AND column_name = '{column}'
                """)
                result = db.execute(check_sql).fetchone()
                
                if not result:
                    print(f"  ➕ Adicionando coluna {table}.{column}...")
                    db.execute(text(sql))
                    db.commit()
                    print(f"     ✅ Coluna {column} criada!")
                else:
                    print(f"  ✓ Coluna {table}.{column} já existe.")
            except Exception as e:
                print(f"  ⚠️ Erro ao adicionar {table}.{column}: {e}")
                db.rollback()
        
        # 2. Cria novas tabelas (se não existirem)
        print("\n🔄 Criando tabelas novas...")
        Base.metadata.create_all(bind=engine)
        
        print("\n✅ Migração concluída!")
        
    finally:
        db.close()

if __name__ == "__main__":
    run_migration()
