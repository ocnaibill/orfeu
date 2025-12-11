import os
import httpx
import uuid
from fastapi import HTTPException

# Pega as configs das variáveis de ambiente
SLSKD_URL = os.getenv("SLSKD_API_URL", "http://slskd:5030/api/v0").rstrip("/")
API_KEY = os.getenv("SLSKD_API_KEY")

async def search_slskd(query: str):
    """
    Envia um pedido de busca para o Slskd.
    """
    if not API_KEY:
        raise HTTPException(status_code=500, detail="SLSKD_API_KEY não configurada no .env")

    headers = {
        "X-API-KEY": API_KEY,
        "Content-Type": "application/json"
    }

    # O Slskd exige que o ID seja um UUID válido.
    search_id = str(uuid.uuid4())

    payload = {
        "id": search_id,
        "searchText": query
    }

    # Debug
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
    """
    Busca os resultados de uma pesquisa em andamento.
    """
    if not API_KEY:
        raise HTTPException(status_code=500, detail="SLSKD_API_KEY não configurada")

    headers = {"X-API-KEY": API_KEY}
    
    async with httpx.AsyncClient() as client:
        try:
            # GET /searches/{id}/responses
            url = f"{SLSKD_URL}/searches/{search_id}/responses"
            response = await client.get(url, headers=headers)
            
            if response.status_code == 200:
                return response.json()
            return []
        except Exception as e:
            print(f"❌ Erro ao buscar resultados: {e}")
            return []

async def download_slskd(username: str, filename: str, size: int = None):
    """
    Solicita o download de um arquivo específico.
    É crucial passar o 'size' para evitar TransferSizeMismatchException.
    """
    if not API_KEY:
        raise HTTPException(status_code=500, detail="SLSKD_API_KEY ausente")

    headers = {
        "X-API-KEY": API_KEY,
        "Content-Type": "application/json"
    }

    # PAYLOAD: Montamos o objeto do arquivo.
    # Se 'size' não for enviado, o Slskd assume 0 e aborta quando os bytes reais chegam.
    file_obj = {
        "filename": filename
    }
    
    if size is not None:
        file_obj["size"] = size

    payload = [file_obj]

    # CORREÇÃO FINAL: Username faz parte da URL
    # Endpoint: POST /api/v0/transfers/downloads/{username}
    endpoint = f"{SLSKD_URL}/transfers/downloads/{username}"

    print(f"\n================ DOWNLOAD DEFINITIVO ================")
    print(f"🎯 Alvo: {endpoint}")
    print(f"📦 Payload: {payload}")
    print(f"=====================================================\n")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(endpoint, json=payload, headers=headers)
            
            # Aceitamos 200 (OK), 201 (Created) ou 204 (No Content)
            if response.status_code not in [200, 201, 204]:
                 print(f"❌ Erro Slskd ({response.status_code}): {response.text}")
                 raise HTTPException(status_code=response.status_code, detail=f"Slskd Error: {response.text}")
            
            return {"status": "Download queued", "file": filename}
            
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))