from fastapi.concurrency import run_in_threadpool
from rapidfuzz import fuzz
from sqlalchemy import desc

# Imports dos seus serviços existentes (ajuste se necessário)
from app.services.release_date_provider import ReleaseDateProvider
from app.services.catalog_provider import CatalogProvider # Assumindo que esteja aqui
from app.utils.text import normalize_text # Assumindo utils

class MusicRecommender:
    """
    Gerencia a lógica de recomendação:
    1. Favoritos (Ouro)
    2. Relacionados/Gênero (Prata) - NOVO
    3. Global (Bronze/Fallback)
    """

    async def get_new_releases(self, top_artists: list[str], limit: int = 10) -> list[dict]:
        news = []
        seen_titles = set()

        # --- FASE 1: Artistas Favoritos (Ouro) ---
        if top_artists:
            print(f"🌟 Buscando novidades para favoritos: {top_artists}")
            favorites_news = await self._process_artists_list(top_artists)
            self._add_unique(news, favorites_news, seen_titles)

        # --- FASE 2: Artistas Relacionados (Prata) ---
        # Se não encheu a lista, busca artistas parecidos
        if len(news) < limit:
            print(f"🔍 Faltam slots ({len(news)}/{limit}). Buscando artistas relacionados...")
            related_artists = await self._get_related_artists_names(top_artists)
            
            if related_artists:
                related_news = await self._process_artists_list(related_artists, is_fallback=True)
                self._add_unique(news, related_news, seen_titles)

        # --- FASE 3: Fallback Global (Bronze) ---
        if len(news) < 3: # Mantendo sua regra de mínimo de 3
            print("🌍 Complementando com Top Albums globais...")
            try:
                global_results = await run_in_threadpool(CatalogProvider.search_catalog, "Top Albums", "album", 10)
                formatted_global = [self._format_item(item, is_global=True) for item in global_results]
                self._add_unique(news, formatted_global, seen_titles)
            except Exception as e:
                print(f"⚠️ Erro no fallback global: {e}")

        return news[:limit]

    async def _process_artists_list(self, artists: list[str], is_fallback: bool = False) -> list[dict]:
        """
        Processa uma lista de artistas buscando álbuns, filtrando ano e desempatando datas.
        """
        results_list = []
        
        for artist in artists:
            try:
                # 1. Busca no CatalogProvider
                results = await run_in_threadpool(CatalogProvider.search_catalog, artist, "album", 10)
                if not results: continue

                # 2. Filtra por nome (Fuzzy Match)
                artist_albums = [
                    r for r in results 
                    if fuzz.partial_ratio(normalize_text(artist), normalize_text(r['artistName'])) > 80
                ]
                if not artist_albums: continue

                # 3. Encontra o ano mais recente
                artist_albums.sort(key=lambda x: x.get('year') or "0000", reverse=True)
                latest_year = artist_albums[0].get('year')
                
                # Filtra candidatos desse ano
                candidates = [a for a in artist_albums if a.get('year') == latest_year]
                winner = candidates[0]

                # 4. TIRA-TEIMA (Lógica do ReleaseDateProvider)
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

                    candidates.sort(key=lambda x: x['releaseDate'], reverse=True)
                    winner = candidates[0]
                
                # 5. Formata o vencedor
                item = self._format_item(winner, is_fallback)
                results_list.append(item)

            except Exception as e:
                print(f"⚠️ Erro processando {artist}: {e}")
                continue
        
        return results_list

    async def _get_related_artists_names(self, source_artists: list[str]) -> list[str]:
        """
        Tenta descobrir artistas relacionados.
        OBS: Como o CatalogProvider (YTMusic) não retorna 'related' facilmente na busca padrão,
        podemos tentar buscar playlists de 'Radio' ou usar uma lógica de gênero se disponível.
        Por enquanto, vamos simular buscando 'Similar to [Artist]' ou retornando vazio para não quebrar.
        """
        # TODO: Implementar lógica real se o CatalogProvider permitir.
        # Exemplo simples: Se o artista é X, tenta buscar "X Radio" e pegar os artistas das primeiras faixas.
        return [] 

    def _format_item(self, winner: dict, is_global: bool = False, is_fallback: bool = False) -> dict:
        color = "#4A00E0" if is_global else f"#{hash(winner['artistName']) & 0xFFFFFF:06x}"
        return {
            "title": winner['collectionName'],
            "artist": winner['artistName'],
            "imageUrl": winner['artworkUrl'],
            "type": "album",
            "id": winner['collectionId'],
            "vibrantColorHex": color,
            "tags": ["Recomendado"] if is_fallback else []
        }

    def _add_unique(self, target_list, new_items, seen_set):
        for item in new_items:
            if item['title'] not in seen_set:
                target_list.append(item)
                seen_set.add(item['title'])