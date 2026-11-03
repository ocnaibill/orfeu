import os
import json
import subprocess
import mutagen
from mutagen.flac import FLAC, Picture
from mutagen.id3 import ID3, APIC, TIT2, TPE1, TALB, TYER
from mutagen.mp4 import MP4, MP4Cover
from fastapi import HTTPException
from app.core import config

# Constantes
TIERS = {
    "low": "128k",
    "medium": "192k",
    "high": "320k",
    "lossless": "original"
}

class AudioManager:
    BASE_PATH = config.MUSIC_DIR

    @staticmethod
    def _safe_join(base: str, relative: str):
        """Junta base + relative e devolve None se o resultado escapar de base (../, symlinks)."""
        base_real = os.path.realpath(base)
        candidate = os.path.realpath(os.path.join(base_real, relative))
        if candidate == base_real or not candidate.startswith(base_real + os.sep):
            return None
        return candidate

    @staticmethod
    def find_local_file(filename: str) -> str:
        sanitized_filename = filename.replace("\\", "/").lstrip("/")

        # PRIMEIRO: caminho completo, confinado a BASE_PATH
        full_path = AudioManager._safe_join(AudioManager.BASE_PATH, sanitized_filename)
        if full_path and os.path.isfile(full_path):
            return full_path

        # SEGUNDO: busca por nome de arquivo (fallback de compatibilidade)
        target_file_name = os.path.basename(sanitized_filename)
        if not target_file_name or target_file_name in (".", ".."):
            raise HTTPException(status_code=404, detail="Ficheiro não encontrado.")

        base_real = os.path.realpath(AudioManager.BASE_PATH)
        matches = []
        for root, dirs, files in os.walk(base_real):
            if target_file_name in files:
                found_path = os.path.join(root, target_file_name)
                rel_path = os.path.relpath(found_path, base_real)
                if rel_path.lower() == sanitized_filename.lower():
                    return found_path
                matches.append(found_path)

        if matches:
            if len(matches) > 1:
                print(f"⚠️ Múltiplos arquivos encontrados para '{target_file_name}': {matches}")
            return matches[0]

        raise HTTPException(status_code=404, detail="Ficheiro não encontrado.")

    @staticmethod
    def get_audio_tags(file_path: str) -> dict:
        tags = {"title": None, "artist": None, "album": None, "genre": None, "date": None}
        try:
            audio = mutagen.File(file_path, easy=True)
            if audio:
                tags["title"] = audio.get("title", [None])[0]
                tags["artist"] = audio.get("artist", [None])[0]
                tags["album"] = audio.get("album", [None])[0]
                tags["genre"] = audio.get("genre", [None])[0]
                tags["date"] = audio.get("date", [None])[0] or audio.get("year", [None])[0]
        except Exception as e:
            print(f"⚠️ Erro Mutagen: {e}")
        return tags

    @staticmethod
    def get_audio_metadata(file_path: str) -> dict:
        tech_data = {}
        try:
            cmd = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", file_path]
            result = subprocess.run(cmd, capture_output=True, text=True)
            data = json.loads(result.stdout)
            
            audio_stream = next((s for s in data.get('streams', []) if s['codec_type'] == 'audio'), None)
            format_info = data.get('format', {})
            
            if audio_stream:
                codec = audio_stream.get('codec_name', 'unknown')
                sample_rate = int(audio_stream.get('sample_rate', 0))
                bits = audio_stream.get('bits_per_raw_sample') or audio_stream.get('bits_per_sample')
                
                tech_label = f"{sample_rate}Hz"
                if bits: tech_label = f"{bits}bit/{tech_label}"
                
                tech_data = {
                    "format": codec,
                    "bitrate": int(format_info.get('bit_rate', 0)),
                    "sample_rate": sample_rate,
                    "channels": audio_stream.get('channels'),
                    "duration": float(format_info.get('duration', 0)),
                    "tech_label": tech_label,
                    "is_lossless": codec in ['flac', 'wav', 'alac']
                }
        except Exception:
            pass

        artistic_data = AudioManager.get_audio_tags(file_path)
        
        # Fallback de Título
        if not artistic_data["title"]:
            artistic_data["title"] = os.path.splitext(os.path.basename(file_path))[0]

        return {
            "filename": os.path.basename(file_path),
            "path": file_path, # Útil internamente
            **tech_data,
            **artistic_data
        }
    
    # --- NOVO: Função para Gravar Tags e Capa ---
    @staticmethod
    def embed_metadata(file_path: str, metadata: dict, cover_data: bytes = None):
        """
        Escreve tags (Artist, Title, Album) e embuti a capa no arquivo.
        """
        try:
            print(f"🏷️ Aplicando tags em: {os.path.basename(file_path)}")
            
            # Detecção via extensão (mais rápido que mutagen.File para escrita especifica)
            ext = file_path.lower().split('.')[-1]
            
            if ext == 'flac':
                audio = FLAC(file_path)
                audio['title'] = metadata.get('title', '')
                audio['artist'] = metadata.get('artist', '')
                audio['album'] = metadata.get('album', '')
                
                if cover_data:
                    pic = Picture()
                    pic.type = 3 # Front Cover
                    pic.mime = 'image/jpeg'
                    pic.desc = 'Cover'
                    pic.data = cover_data
                    audio.clear_pictures()
                    audio.add_picture(pic)
                audio.save()

            elif ext == 'mp3':
                try:
                    audio = ID3(file_path)
                except:
                    audio = ID3() # Cria se não existir
                
                audio.add(TIT2(encoding=3, text=metadata.get('title', '')))
                audio.add(TPE1(encoding=3, text=metadata.get('artist', '')))
                audio.add(TALB(encoding=3, text=metadata.get('album', '')))
                
                if cover_data:
                    audio.add(APIC(
                        encoding=3,
                        mime='image/jpeg',
                        type=3, 
                        desc='Cover',
                        data=cover_data
                    ))
                audio.save(file_path)
            
            # Adicionar suporte a M4A/MP4 se necessário no futuro (mutagen.mp4)
            
            print("✅ Tags aplicadas com sucesso.")
            
        except Exception as e:
            print(f"❌ Erro ao aplicar tags: {e}")

    @staticmethod
    def transcode_stream(file_path: str, quality: str):
        target_bitrate = TIERS.get(quality, "128k")
        cmd = ["ffmpeg", "-i", file_path, "-f", "mp3", "-ab", target_bitrate, "-vn", "-map", "0:a:0", "-"]
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=10**6)
        try:
            while True:
                chunk = process.stdout.read(64 * 1024)
                if not chunk: break
                yield chunk
        finally:
            process.kill()

    @staticmethod
    def extract_cover_stream(file_path: str):
        cmd = ["ffmpeg", "-i", file_path, "-an", "-c:v", "mjpeg", "-f", "mjpeg", "-v", "error", "-"]
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=10**6)
        try:
            while True:
                chunk = process.stdout.read(64 * 1024)
                if not chunk: break
                yield chunk
        finally:
            process.kill()