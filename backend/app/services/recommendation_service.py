from fastapi.concurrency import run_in_threadpool
from sqlalchemy import desc
from rapidfuzz import fuzz
from unidecode import unidecode
import random

from app.services.release_date_provider import ReleaseDateProvider
from app.services.catalog_provider import CatalogProvider
from app.services.tidal_provider import TidalProvider

def normalize_text(text: str) -> str:
    """Helper local para normalização"""
    if not text: return ""
    return unidecode(text.lower().replace("$", "s").replace("&", "and")).strip()

class MusicRecommender:
    """
    Gerencia a lógica de recomendação:
    1. Favoritos (Ouro) - Verifica ano e faz tira-teima de data usando ReleaseDateProvider.
    2. Relacionados (Prata) - Busca artistas similares (futuro).
    3. SEM FALLBACK GLOBAL PARA ESTA ROTA.
    """

    async def get_new_releases(self, top_artists: list[str], limit: int = 10) -> list[dict]:
        news = []
        seen_titles = set()

        # --- FASE 1: Artistas Favoritos (Ouro) ---
        if top_artists:
            print(f"🌟 Buscando novidades estritas para: {top_artists}")
            favorites_news = await self._process_artists_list(top_artists)
            self._add_unique(news, favorites_news, seen_titles)

        # --- FASE 2: Artistas Relacionados (Prata - Opcional) ---
        if len(news) < limit:
            # Espaço reservado para buscar "Similares" no futuro, 
            # mas SEM preencher com Top Global.
            pass

        return news[:limit]

    async def _process_artists_list(self, artists: list[str], is_fallback: bool = False) -> list[dict]:
        """
        Processa uma lista de artistas buscando álbuns e usando ReleaseDateProvider para precisão.
        """
        results_list = []
        
        for artist in artists:
            try:
                # 1. Busca no CatalogProvider (YTMusic)
                results = await run_in_threadpool(CatalogProvider.search_catalog, artist, "album", 10)
                if not results: continue

                # 2. Filtra por nome (STRICT MATCH)
                # Mudança Crítica: Usamos token_sort_ratio > 90 para evitar falsos positivos
                # Isso impede que "Laufey" dê match com "The Moon" ou bandas aleatórias
                artist_clean = normalize_text(artist)
                artist_albums = []
                
                for r in results:
                    r_artist_clean = normalize_text(r['artistName'])
                    # Verifica match muito forte ou contêm o nome exato
                    if fuzz.token_sort_ratio(artist_clean, r_artist_clean) > 90 or artist_clean == r_artist_clean:
                        artist_albums.append(r)
                
                if not artist_albums: continue

                # 3. Encontra o ano mais recente
                artist_albums.sort(key=lambda x: str(x.get('year') or "0000"), reverse=True)
                latest_year = artist_albums[0].get('year')
                
                if not latest_year: continue

                # Filtra candidatos desse ano
                candidates = [a for a in artist_albums if a.get('year') == latest_year]
                winner = candidates[0]

                # 4. TIRA-TEIMA (USO DO RELEASE DATE PROVIDER)
                # Se houver empate no ano (ex: 3 singles em 2025), busca data exata no iTunes
                if len(candidates) > 1:
                    print(f"   ⚔️ Empate em {latest_year} para {artist}. Buscando datas exatas...")
                    for cand in candidates:
                        exact_date = await run_in_threadpool(
                            ReleaseDateProvider.get_exact_date, 
                            artist, 
                            cand['collectionName']
                        )
                        cand['releaseDate'] = exact_date or f"{latest_year}-01-01"
                        print(f"      -> {cand['collectionName']}: {cand['releaseDate']}")

                    # Ordena pela data completa
                    candidates.sort(key=lambda x: x['releaseDate'], reverse=True)
                    winner = candidates[0]
                
                # 5. Formata o vencedor
                item = self._format_item(winner, is_fallback=is_fallback)
                results_list.append(item)

            except Exception as e:
                print(f"⚠️ Erro processando {artist}: {e}")
                continue
        
        return results_list

    def _format_item(self, winner: dict, is_global: bool = False, is_fallback: bool = False) -> dict:
        color = "#4A00E0" if is_global else f"#{hash(winner['artistName']) & 0xFFFFFF:06x}"
        return {
            "title": winner['collectionName'],
            "artist": winner['artistName'],
            "imageUrl": winner['artworkUrl'],
            "type": "album",
            "id": winner['collectionId'],
            "vibrantColorHex": color,
            "tags": ["Global"] if is_global else []
        }

    def _add_unique(self, target_list, new_items, seen_set):
        for item in new_items:
            key = f"{item['title']}-{item['artist']}"
            if key not in seen_set:
                target_list.append(item)
                seen_set.add(key)