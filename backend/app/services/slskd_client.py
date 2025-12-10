import os
import httpx
import uuid # <--- IMPORTANTE: Importar biblioteca de UUID
from fastapi import HTTPException

# Pega as configs das variáveis de ambiente
# Garantindo que usamos a v0 que descobrimos ser a correta
SLSKD_URL = os.getenv("SLSKD_API_URL", "http://slskd:5030/api/v0")
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

    # --- CORREÇÃO AQUI ---
    # O Slskd exige que o ID seja um UUID válido.
    # Não podemos usar "daft punk" como ID.
    search_id = str(uuid.uuid4())

    payload = {
        "id": search_id,     # ID técnico (UUID)
        "searchText": query  # O que buscar (ex: "daft punk")
    }

    # Debug para garantir que estamos mandando certo
    print(f"📡 Enviando busca para: {SLSKD_URL}/searches")
    print(f"📦 Payload: {payload}")

    async with httpx.AsyncClient() as client:
        try:
            # POST /searches
            response = await client.post(f"{SLSKD_URL}/searches", json=payload, headers=headers)
            response.raise_for_status()
            
            return {
                "status": "Search initiated", 
                "search_id": search_id, # Retornamos o UUID para o frontend poder consultar depois
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
            # Importante: search_id aqui tem que ser o UUID que geramos no passo anterior
            url = f"{SLSKD_URL}/searches/{search_id}/responses"
            print(f"🔍 Consultando resultados em: {url}")
            
            response = await client.get(url, headers=headers)
            
            if response.status_code == 200:
                return response.json()
            else:
                print(f"⚠️ Status inesperado ao buscar resultados: {response.status_code}")
                return []
        except Exception as e:
            print(f"❌ Erro ao buscar resultados: {e}")
            return []