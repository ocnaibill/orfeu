from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import RedirectResponse, HTMLResponse
import os
import json

from app.core import config

router = APIRouter(tags=["system"])

def get_update_config() -> dict:
    config_path = config.UPDATES_CONFIG_PATH
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            return json.load(f)
    return {"latest_version": "0.0.0"}

@router.get("/")
def read_root(request: Request):
    """
    Rota raiz: 
    - Se acessado de navegador: redireciona para /app (web app)
    - Se acessado de API: retorna status JSON
    """
    # Verifica se é um navegador pelo header Accept
    accept = request.headers.get("accept", "")
    user_agent = request.headers.get("user-agent", "").lower()
    
    # Se é um navegador pedindo HTML e o web app existe
    is_browser = "text/html" in accept or "mozilla" in user_agent or "chrome" in user_agent
    web_app_exists = os.path.exists(f"{config.WEB_APP_DIR}/index.html")
    
    if is_browser and web_app_exists:
        return RedirectResponse(url="/app", status_code=302)
    
    # Caso contrário, retorna status da API
    return {"status": "Orfeu is alive", "service": "Backend", "version": config.API_VERSION}

@router.get("/install", response_class=HTMLResponse)
async def install_page():
    """
    Página simples para listar e baixar os arquivos de atualização.
    Útil para debug e para o usuário baixar manualmente.
    """
    files = os.listdir(config.PUBLIC_DIR)
    files.sort()
    
    html_content = """
    <html>
        <head>
            <title>Instalar Orfeu</title>
            <style>
                body { font-family: sans-serif; background: #121212; color: white; padding: 20px; }
                h1 { color: #D4AF37; }
                a { display: block; padding: 10px; background: #222; margin: 5px 0; color: #D4AF37; text-decoration: none; border-radius: 5px; }
                a:hover { background: #333; }
            </style>
        </head>
        <body>
            <h1>Downloads Disponíveis</h1>
    """
    
    if not files:
        html_content += "<p>Nenhum arquivo encontrado no servidor.</p>"
    else:
        for f in files:
            html_content += f'<a href="/downloads/{f}">⬇️ {f}</a>'
            
    html_content += "</body></html>"
    return html_content

@router.get("/latest")
async def download_latest(request: Request):
    """
    Detecta o sistema operacional pelo User-Agent e redireciona para o download
    da última versão disponível para aquela plataforma.
    """
    user_agent = request.headers.get("user-agent", "").lower()
    
    # Detecta a plataforma pelo User-Agent
    if "android" in user_agent:
        platform = "android"
    elif "windows" in user_agent:
        platform = "windows"
    elif "macintosh" in user_agent or "mac os" in user_agent:
        platform = "macos"
    elif "linux" in user_agent:
        # Linux desktop - oferece a versão Windows (AppImage/tar.gz seria melhor, mas não temos)
        # Por enquanto redireciona para a página de instalação
        platform = "linux"
    elif "iphone" in user_agent or "ipad" in user_agent:
        platform = "ios"
    else:
        platform = "unknown"
    
    # Busca a URL do updates.json
    try:
        config = get_update_config()
        latest_version = config.get("latest_version", "0.0.0")
        platforms = config.get("platforms", {})
        
        if platform in platforms and "url" in platforms[platform]:
            download_url = platforms[platform]["url"]
            return RedirectResponse(url=download_url, status_code=302)
        
        # Se não tem URL específica para a plataforma, mostra página informativa
        html_content = f"""
        <html>
            <head>
                <title>Download Orfeu</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {{ 
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                        background: #121212; 
                        color: white; 
                        padding: 20px; 
                        text-align: center;
                        min-height: 100vh;
                        display: flex;
                        flex-direction: column;
                        justify-content: center;
                        align-items: center;
                    }}
                    h1 {{ color: #D4AF37; font-size: 2em; margin-bottom: 10px; }}
                    .version {{ color: #888; margin-bottom: 30px; }}
                    .message {{ 
                        background: #222; 
                        padding: 20px 30px; 
                        border-radius: 10px; 
                        margin: 20px 0;
                        max-width: 400px;
                    }}
                    a {{ 
                        display: inline-block;
                        padding: 15px 30px; 
                        background: #D4AF37; 
                        color: #121212; 
                        text-decoration: none; 
                        border-radius: 8px; 
                        font-weight: bold;
                        margin: 10px;
                    }}
                    a:hover {{ background: #E5C048; }}
                    .platforms {{ margin-top: 20px; }}
                    .platform-link {{ 
                        display: block; 
                        padding: 12px 20px; 
                        background: #333; 
                        color: #D4AF37; 
                        margin: 8px auto;
                        border-radius: 5px;
                        max-width: 300px;
                    }}
                </style>
            </head>
            <body>
                <h1>🎵 Orfeu</h1>
                <p class="version">Versão {latest_version}</p>
        """
        
        if platform == "ios":
            html_content += """
                <div class="message">
                    <p>📱 O Orfeu ainda não está disponível para iOS.</p>
                    <p>Por enquanto, está disponível para Android, Windows e macOS.</p>
                </div>
            """
        elif platform == "linux":
            html_content += """
                <div class="message">
                    <p>🐧 Versão Linux em breve!</p>
                    <p>Por enquanto, você pode usar o app no Windows, macOS ou Android.</p>
                </div>
            """
        else:
            html_content += """
                <div class="message">
                    <p>Não conseguimos detectar seu sistema operacional.</p>
                    <p>Escolha uma das opções abaixo:</p>
                </div>
            """
        
        html_content += '<div class="platforms">'
        for plat, data in platforms.items():
            icon = {"android": "📱", "windows": "🪟", "macos": "🍎"}.get(plat, "📦")
            name = {"android": "Android (APK)", "windows": "Windows", "macos": "macOS"}.get(plat, plat)
            html_content += f'<a href="{data["url"]}" class="platform-link">{icon} {name}</a>'
        html_content += '</div>'
        
        html_content += """
            </body>
        </html>
        """
        return HTMLResponse(content=html_content)
        
    except Exception as e:
        print(f"❌ Erro no /latest: {e}")
        # Fallback para a página de instalação
        return RedirectResponse(url="/install", status_code=302)

@router.get("/app/latest_version")
def latest_version_check():
    try:
        return get_update_config()
    except Exception as e:
        print(f"❌ Erro config update: {e}")
        raise HTTPException(500, detail="Erro de configuração.")
