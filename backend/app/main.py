from fastapi import FastAPI
# Importamos as funções que acabamos de criar
from app.services.slskd_client import search_slskd, get_search_results

app = FastAPI(title="Orfeu API", version="0.1.0")

@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend"}

# --- Rota 1: Iniciar Busca ---
@app.post("/search/{query}")
async def start_search(query: str):
    """
    Envia o comando para o Soulseek buscar uma música.
    """
    return await search_slskd(query)

# --- Rota 2: Ver Resultados ---
@app.get("/results/{search_id}")
async def view_results(search_id: str):
    """
    Vê o que o Soulseek encontrou para aquela busca.
    """
    raw_results = await get_search_results(search_id)
    
    # Processamento simples para limpar o JSON
    files = []
    for response in raw_results:
        # 'response' é um usuário do Soulseek
        if 'files' in response:
            for file in response['files']:
                # Filtro básico: Queremos FLAC ou MP3
                if file['filename'].lower().endswith(('.flac', '.mp3')):
                    files.append({
                        'filename': file['filename'],
                        'size': file['size'],
                        'bitrate': file.get('bitRate'),
                        'speed': response.get('uploadSpeed', 0),
                        'user': response.get('username'),
                        'is_locked': response.get('locked', False)
                    })
    
    # Ordena: Mais rápidos primeiro
    files.sort(key=lambda x: x['speed'], reverse=True)
    
    return files