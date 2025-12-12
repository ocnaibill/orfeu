import os
import httpx
import uuid
from fastapi import HTTPException

# Pega as configs das variáveis de ambiente
SLSKD_URL = os.getenv("SLSKD_API_URL", "http://slskd:5030/api/v0").rstrip("/")
API_KEY = os.getenv("SLSKD_API_KEY")

async def search_slskd(query: str):
    if not API_KEY:
        raise HTTPException(status_code=500, detail="SLSKD_API_KEY não configurada no .env")

    headers = {
        "X-API-KEY": API_KEY,
        "Content-Type": "application/json"
    }

    search_id = str(uuid.uuid4())
    payload = {
        "id": search_id,
        "searchText": query
    }

    print(f"📡 Enviando busca para: {SLSKD_URL}/searches")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(f"{SLSKD_URL}/searches", json=payload, headers=headers)
            response.raise_for_status()
            
            return {
                "status": "Search initiated", 
                "search_id": search_id,
                "query": query,
                "message": "Busca iniciada com sucesso."
            }
        except httpx.HTTPStatusError as e:
            print(f"❌ Erro Slskd ({e.response.status_code}): {e.response.text}")
            raise HTTPException(status_code=e.response.status_code, detail=f"Erro no Soulseek: {e.response.text}")
        except Exception as e:
            print(f"❌ Erro de conexão: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Erro interno: {str(e)}")

async def get_search_results(search_id: str):
    if not API_KEY:
        raise HTTPException(status_code=500, detail="SLSKD_API_KEY não configurada")

    headers = {"X-API-KEY": API_KEY}
    
    async with httpx.AsyncClient() as client:
        try:
            url = f"{SLSKD_URL}/searches/{search_id}/responses"
            response = await client.get(url, headers=headers)
            if response.status_code == 200:
                return response.json()
            return []
        except Exception as e:
            print(f"❌ Erro ao buscar resultados: {e}")
            return []

async def download_slskd(username: str, filename: str, size: int = None):
    if not API_KEY:
        raise HTTPException(status_code=500, detail="SLSKD_API_KEY ausente")

    headers = {
        "X-API-KEY": API_KEY,
        "Content-Type": "application/json"
    }

    file_obj = {"filename": filename}
    if size is not None:
        file_obj["size"] = size

    payload = [file_obj]
    endpoint = f"{SLSKD_URL}/transfers/downloads/{username}"

    print(f"⬇️ Solicitando download em: {endpoint}")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(endpoint, json=payload, headers=headers)
            if response.status_code not in [200, 201, 204]:
                 print(f"❌ Erro Slskd ({response.status_code}): {response.text}")
                 raise HTTPException(status_code=response.status_code, detail=f"Slskd Error: {response.text}")
            return {"status": "Download queued", "file": filename}
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

# --- STATUS GLOBAL MELHORADO ---
async def get_transfer_status(filename: str):
    """
    Busca na lista GLOBAL de downloads ativos do Slskd.
    Lógica de comparação melhorada para encontrar o arquivo mesmo se as pastas diferirem.
    """
    if not API_KEY: return None

    headers = {"X-API-KEY": API_KEY}
    endpoint = f"{SLSKD_URL}/transfers/downloads"

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(endpoint, headers=headers)
            if response.status_code == 200:
                downloads = response.json()
                
                # Normalização do alvo (O que o usuário quer)
                # Ex: "Musica\Artist\Song.mp3" -> "song.mp3"
                target_clean = filename.replace("\\", "/").lower()
                target_simple = os.path.basename(target_clean) 
                
                for item in downloads:
                    # Normalização do remoto (O que está baixando)
                    remote_file = item.get('filename', '').replace("\\", "/").lower()
                    remote_simple = os.path.basename(remote_file)
                    
                    # CORREÇÃO: Comparação mais permissiva
                    # 1. Se o nome do arquivo final for idêntico.
                    # 2. Ou se o caminho completo contiver o nome do arquivo.
                    is_match = (target_simple == remote_simple) or (target_clean in remote_file)
                    
                    if is_match:
                        # Cálculo de progresso mais seguro
                        total = item.get('size', 1)
                        transferred = item.get('bytesTransferred', 0)
                        # Slskd às vezes retorna percentual, às vezes não. Calculamos nós mesmos.
                        percent = (transferred / total) * 100 if total > 0 else 0.0
                        
                        return {
                            "state": item.get('state'),      # Queued, Initializing, Downloading...
                            "bytes_transferred": transferred,
                            "total_bytes": total,
                            "speed": item.get('speed', 0),   # Bytes por segundo
                            "percent": percent,
                            "username": item.get('username')
                        }
            return None 
        except Exception as e:
            print(f"⚠️ Erro ao checar status global: {e}")
            return None