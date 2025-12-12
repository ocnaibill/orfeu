import os
import httpx
import uuid
from urllib.parse import quote # Importante para nomes de usuário com espaços/[brackets]
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
    
    # CORREÇÃO: URL Encode no username para evitar erros com caracteres especiais
    safe_username = quote(username) 
    endpoint = f"{SLSKD_URL}/transfers/downloads/{safe_username}"

    print(f"⬇️ Solicitando download em: {endpoint}")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(endpoint, json=payload, headers=headers)
            
            # TRATAMENTO ESPECIAL PARA PEER OFFLINE (500 do Slskd)
            if response.status_code == 500:
                 print(f"❌ Slskd 500 (Provavelmente Peer Offline): {response.text}")
                 raise HTTPException(status_code=503, detail="O usuário não está disponível (Peer Offline/Unreachable). Tente outro arquivo.")

            if response.status_code not in [200, 201, 204]:
                 print(f"❌ Erro Slskd ({response.status_code}): {response.text}")
                 # Retorna o erro detalhado do Slskd para o Flutter entender
                 raise HTTPException(status_code=response.status_code, detail=f"Slskd Error: {response.text}")
            
            return {"status": "Download queued", "file": filename}
            
        except httpx.HTTPStatusError as e:
            print(f"❌ Erro HTTP Slskd: {e}")
            raise HTTPException(status_code=e.response.status_code, detail=str(e))
        except Exception as e:
            if isinstance(e, HTTPException): raise e # Re-raise se já for nosso
            print(f"❌ Erro Interno Download: {e}")
            raise HTTPException(status_code=500, detail=str(e))

async def get_transfer_status(filename: str):
    if not API_KEY: return None

    headers = {"X-API-KEY": API_KEY}
    endpoint = f"{SLSKD_URL}/transfers/downloads"

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(endpoint, headers=headers)
            if response.status_code == 200:
                downloads = response.json()
                
                target = filename.replace("\\", "/").lower()
                target_simple = os.path.basename(target) 
                
                for item in downloads:
                    remote_file = item.get('filename', '').replace("\\", "/").lower()
                    remote_simple = os.path.basename(remote_file)
                    
                    is_match = (target_simple == remote_simple) or (target in remote_file) or (remote_file in target)
                    
                    if is_match:
                        total = item.get('size', 1)
                        transferred = item.get('bytesTransferred', 0)
                        percent = (transferred / total) * 100 if total > 0 else 0.0
                        
                        # --- TRADUÇÃO DE ESTADOS ---
                        raw_state = item.get('state', 'Unknown')
                        friendly_state = raw_state

                        # Mapeia os estados do Slskd para os que o App espera
                        if 'Completed, Succeeded' in raw_state:
                            friendly_state = 'Completed'
                        elif 'Completed' in raw_state: # Cancelled, TimedOut, Errored
                            friendly_state = 'Aborted'
                        elif 'InProgress' in raw_state:
                            friendly_state = 'Downloading'
                        elif any(s in raw_state for s in ['Queued', 'Requested', 'Initializing']):
                            friendly_state = 'Queued'

                        return {
                            "state": friendly_state,
                            "raw_state": raw_state, # Útil para debug
                            "bytes_transferred": transferred,
                            "total_bytes": total,
                            "speed": item.get('speed', 0),
                            "percent": percent,
                            "username": item.get('username')
                        }
            
            # Se chegou aqui, não achou na lista.
            # Debug para entender por que não achou:
            if len(downloads) > 0:
                print(f"⚠️ Status não encontrado para: {target_simple}")
                # print(f"   Arquivos ativos no Slskd: {[d.get('filename') for d in downloads[:3]]}...")
            
            return None 
        except Exception as e:
            print(f"⚠️ Erro ao checar status global: {e}")
            return None