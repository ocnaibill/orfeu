"""
Configuração de Gêneros Musicais para o Orfeu.

Para adicionar um novo gênero, basta adicionar uma entrada no dicionário GENRES.
O sistema irá automaticamente criar a playlist com as top tracks do gênero.

Formato:
    "Nome do Gênero": {
        "search_query": "termo de busca no Tidal",
        "playlist_id": "UUID da playlist do Tidal (opcional)",
        "color": 0xAARRGGBB,  # Cor em formato hex com alpha
        "icon": "nome_do_icone"  # (futuro) ícone do Flutter
    }

Se playlist_id for fornecido, usa essa playlist do Tidal.
Se não, faz busca por artista/tracks do gênero.
"""

# Mapeamento de gêneros com configurações
GENRES = {
    # === GÊNEROS POPULARES ===
    "Pop": {
        "search_query": "pop hits",
        "playlist_id": "84974059-623e-4a61-8d62-b77ba6e8729e",  # Tidal Pop Hits
        "color": 0xFFE91E63,  # Pink
    },
    "Hip Hop": {
        "search_query": "hip hop rap",
        "playlist_id": "a4c53f62-b593-4abc-98cf-5628e53e3aab",  # Hip Hop Mix
        "color": 0xFFFFC107,  # Amber
    },
    "R&B": {
        "search_query": "r&b soul",
        "playlist_id": "8e1a3d28-5d62-4461-bb95-d8e9a88f0ec8",
        "color": 0xFF9C27B0,  # Purple
    },
    "Rock": {
        "search_query": "rock",
        "playlist_id": "7a5b9dc4-7c7c-4d6b-b8b4-b8b4b8b4b8b4",
        "color": 0xFFF44336,  # Red
    },
    "Electronic": {
        "search_query": "electronic edm",
        "playlist_id": "4d7c7c2d-8e5a-4f7e-9c3d-2e1f3c4d5e6f",
        "color": 0xFF00BCD4,  # Cyan
    },
    "Latin": {
        "search_query": "latin reggaeton",
        "playlist_id": "3c2d1e4f-5a6b-7c8d-9e0f-1a2b3c4d5e6f",
        "color": 0xFFFF5722,  # Deep Orange
    },
    
    # === GÊNEROS CLÁSSICOS ===
    "Jazz": {
        "search_query": "jazz",
        "color": 0xFF795548,  # Brown
    },
    "Blues": {
        "search_query": "blues",
        "color": 0xFF3F51B5,  # Indigo
    },
    "Classical": {
        "search_query": "classical orchestra",
        "color": 0xFF607D8B,  # Blue Grey
    },
    "Soul": {
        "search_query": "soul music",
        "color": 0xFFFF9800,  # Orange
    },
    
    # === GÊNEROS ALTERNATIVOS ===
    "Indie": {
        "search_query": "indie alternative",
        "color": 0xFF4CAF50,  # Green
    },
    "Alternative": {
        "search_query": "alternative rock",
        "color": 0xFF8BC34A,  # Light Green
    },
    "Punk": {
        "search_query": "punk rock",
        "color": 0xFF000000,  # Black
    },
    "Metal": {
        "search_query": "heavy metal",
        "color": 0xFF424242,  # Dark Grey
    },
    
    # === GÊNEROS ELETRÔNICOS ===
    "House": {
        "search_query": "house music",
        "color": 0xFF673AB7,  # Deep Purple
    },
    "Techno": {
        "search_query": "techno",
        "color": 0xFF1A237E,  # Dark Blue
    },
    "Lo-Fi": {
        "search_query": "lo-fi beats",
        "color": 0xFF9575CD,  # Light Purple
    },
    "Drum & Bass": {
        "search_query": "drum and bass dnb",
        "color": 0xFFE65100,  # Dark Orange
    },
    
    # === GÊNEROS BRASILEIROS ===
    "Bossa Nova": {
        "search_query": "bossa nova",
        "color": 0xFF26A69A,  # Teal
    },
    "MPB": {
        "search_query": "mpb música popular brasileira",
        "color": 0xFF009688,  # Teal
    },
    "Samba": {
        "search_query": "samba brasileiro",
        "color": 0xFFFFEB3B,  # Yellow
    },
    "Funk Brasileiro": {
        "search_query": "funk brasileiro",
        "color": 0xFFE040FB,  # Purple Accent
    },
    "Sertanejo": {
        "search_query": "sertanejo",
        "color": 0xFF8D6E63,  # Brown
    },
    "Forró": {
        "search_query": "forró",
        "color": 0xFFFF7043,  # Deep Orange
    },
    
    # === GÊNEROS INTERNACIONAIS ===
    "K-Pop": {
        "search_query": "k-pop korean pop",
        "color": 0xFFEC407A,  # Pink
    },
    "J-Pop": {
        "search_query": "j-pop japanese pop",
        "color": 0xFFEF5350,  # Red
    },
    "Reggae": {
        "search_query": "reggae",
        "color": 0xFF43A047,  # Green
    },
    "Afrobeats": {
        "search_query": "afrobeats african",
        "color": 0xFFFF6F00,  # Amber
    },
    
    # === MOOD / AMBIENTE ===
    "Chill": {
        "search_query": "chill vibes",
        "color": 0xFF81D4FA,  # Light Blue
    },
    "Acoustic": {
        "search_query": "acoustic",
        "color": 0xFFBCAAA4,  # Brown
    },
    "Instrumental": {
        "search_query": "instrumental",
        "color": 0xFF90A4AE,  # Blue Grey
    },
    "Ambient": {
        "search_query": "ambient",
        "color": 0xFFB2DFDB,  # Teal Light
    },
    
    # === DÉCADAS ===
    "80s": {
        "search_query": "80s hits",
        "color": 0xFFD500F9,  # Purple Accent
    },
    "90s": {
        "search_query": "90s hits",
        "color": 0xFF651FFF,  # Deep Purple Accent
    },
    "2000s": {
        "search_query": "2000s hits",
        "color": 0xFF536DFE,  # Indigo Accent
    },
    
    # === OUTROS ===
    "Country": {
        "search_query": "country music",
        "color": 0xFF6D4C41,  # Brown
    },
    "Gospel": {
        "search_query": "gospel christian",
        "color": 0xFFFFD54F,  # Amber
    },
    "Soundtrack": {
        "search_query": "movie soundtrack",
        "color": 0xFF546E7A,  # Blue Grey
    },
    "Jazz Pop": {
        "search_query": "jazz pop",
        "color": 0xFFFFB74D,  # Orange
    },
}


def get_all_genres():
    """Retorna todos os gêneros configurados."""
    return [
        {
            "name": name,
            "color": config.get("color", 0xFF9E9E9E),
            "search_query": config.get("search_query", name),
            "playlist_id": config.get("playlist_id"),
        }
        for name, config in GENRES.items()
    ]


def get_genre_config(genre_name: str):
    """Retorna a configuração de um gênero específico."""
    return GENRES.get(genre_name)


def get_featured_genres(limit: int = 12):
    """
    Retorna os gêneros em destaque (primeiros da lista).
    Útil para a seção 'Conheça mais'.
    """
    featured = list(GENRES.keys())[:limit]
    return [
        {
            "name": name,
            "color": GENRES[name].get("color", 0xFF9E9E9E),
            "search_query": GENRES[name].get("search_query", name),
            "playlist_id": GENRES[name].get("playlist_id"),
        }
        for name in featured
    ]
