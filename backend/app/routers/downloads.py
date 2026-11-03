import os

from fastapi import APIRouter, HTTPException, BackgroundTasks, Depends

from app.deps import get_current_user
from app.schemas import DownloadRequest, AutoDownloadRequest, SmartDownloadRequest
from app.services.audio_manager import AudioManager
from app.sources.registry import get_sources

router = APIRouter(tags=["downloads"])

@router.post("/download/smart", dependencies=[Depends(get_current_user)])
async def smart_download(request: SmartDownloadRequest, background_tasks: BackgroundTasks):
    return await get_sources().downloads.smart_download(request, background_tasks)

@router.post("/search/{query}", dependencies=[Depends(get_current_user)])
async def start_search_legacy(query: str): return await get_sources().soulseek.start_search(query)

@router.get("/results/{search_id}", dependencies=[Depends(get_current_user)])
async def view_results(search_id: str): return await get_sources().soulseek.search_results(search_id)

@router.post("/download", dependencies=[Depends(get_current_user)])
async def queue_download(request: DownloadRequest):
    try:
        path = AudioManager.find_local_file(request.filename)
        if os.path.getsize(path) > 0: return {"status": "Already downloaded", "file": request.filename}
        else: os.remove(path)
    except HTTPException: pass
    return await get_sources().soulseek.queue_download(request.username, request.filename, request.size)

@router.get("/download/status", dependencies=[Depends(get_current_user)])
async def check_download_status(filename: str):
    try:
        path = AudioManager.find_local_file(filename)
        size = os.path.getsize(path)
        if "Tidal" in path and size > 1000000:
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Tidal Download"}
        if size > 0 and "Tidal" not in path: 
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Pronto"}
    except HTTPException: pass
    status = await get_sources().soulseek.transfer_status(filename)
    if status: return status
    return {"state": "Unknown", "progress": 0.0, "message": "Iniciando"}

@router.post("/download/auto", dependencies=[Depends(get_current_user)])
async def auto_download_best(request: AutoDownloadRequest):
    # Endpoint legado: nunca foi implementado (ignorava o search_id e baixava
    # artista/faixa vazios). Falha de forma explícita em vez de baixar lixo.
    raise HTTPException(status_code=501, detail="Endpoint legado sem implementação. Use POST /download/smart.")
