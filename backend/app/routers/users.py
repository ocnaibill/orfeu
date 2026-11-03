import os

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import desc, func
from sqlalchemy.orm import Session

from app import auth_utils, models
from app.core import config
from app.database import get_db
from app.deps import get_current_user
from app.schemas import ProfileImageUpload, ProfileUpdate

router = APIRouter(tags=["users"])


@router.get("/users/me")
def read_users_me(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Calcula horas totais ouvidas
    total_seconds = db.query(func.sum(models.ListenHistory.duration_listened))\
        .filter(models.ListenHistory.user_id == current_user.id)\
        .scalar() or 0
    
    # Top gêneros (do histórico)
    top_genres = db.query(models.Track.genre, func.count(models.ListenHistory.id).label('count'))\
        .join(models.ListenHistory)\
        .filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.genre.isnot(None),
            models.Track.genre != ''
        )\
        .group_by(models.Track.genre)\
        .order_by(desc('count'))\
        .limit(5)\
        .all()
    
    # Total de playlists
    playlist_count = db.query(models.Playlist).filter(models.Playlist.user_id == current_user.id).count()
    
    # Total de favoritos
    favorites_count = db.query(models.Favorite).filter(models.Favorite.user_id == current_user.id).count()
    
    return {
        "username": current_user.username, 
        "full_name": current_user.full_name,
        "email": current_user.email,
        "profile_image_url": current_user.profile_image_url,
        "stats": {
            "hours_listened": round(total_seconds / 3600, 1),
            "minutes_listened": int(total_seconds / 60),
            "top_genres": [{"genre": g, "plays": c} for g, c in top_genres],
            "playlist_count": playlist_count,
            "favorites_count": favorites_count
        },
        "created_at": current_user.created_at.isoformat() if current_user.created_at else None
    }

@router.put("/users/me")
def update_profile(profile: ProfileUpdate, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """Atualiza dados do perfil do usuário"""
    if profile.full_name is not None:
        current_user.full_name = profile.full_name
    if profile.email is not None:
        # Verifica se email já está em uso por outro usuário
        existing = db.query(models.User).filter(
            models.User.email == profile.email, 
            models.User.id != current_user.id
        ).first()
        if existing:
            raise HTTPException(400, "Email já está em uso")
        current_user.email = profile.email
    if profile.profile_image_url is not None:
        current_user.profile_image_url = profile.profile_image_url
    
    # Alteração de senha
    if profile.new_password is not None:
        if not profile.current_password:
            raise HTTPException(400, "Senha atual é obrigatória")
        # Verifica senha atual
        if not auth_utils.verify_password(profile.current_password, current_user.hashed_password):
            raise HTTPException(400, "Senha atual incorreta")
        # Atualiza para nova senha
        current_user.hashed_password = auth_utils.get_password_hash(profile.new_password)
    
    db.commit()
    db.refresh(current_user)
    
    return {"status": "updated", "username": current_user.username}

@router.post("/users/me/profile-image")
def upload_profile_image(
    upload: ProfileImageUpload,
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(get_current_user)
):
    """
    Faz upload da imagem de perfil do usuário.
    Aceita PNG, JPG, GIF, WebP em formato base64.
    """
    import base64
    import uuid
    
    # Valida tipo de imagem
    allowed_types = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/gif": ".gif",
        "image/webp": ".webp",
    }
    
    if upload.content_type not in allowed_types:
        raise HTTPException(400, f"Tipo de imagem não suportado: {upload.content_type}. Use PNG, JPG, GIF ou WebP.")
    
    extension = allowed_types[upload.content_type]
    
    try:
        # Decodifica base64
        image_bytes = base64.b64decode(upload.image_data)
        
        # Limite de 10MB
        if len(image_bytes) > 10 * 1024 * 1024:
            raise HTTPException(400, "Imagem muito grande. Máximo: 10MB")
        
        # Gera nome único para o arquivo
        filename = f"profile_{current_user.id}_{uuid.uuid4().hex[:8]}{extension}"
        
        # Salva na pasta pública
        profile_images_dir = config.PROFILE_IMAGES_DIR
        os.makedirs(profile_images_dir, exist_ok=True)
        
        filepath = os.path.join(profile_images_dir, filename)
        with open(filepath, "wb") as f:
            f.write(image_bytes)
        
        # Remove imagem antiga se existir
        if current_user.profile_image_url:
            old_filename = current_user.profile_image_url.split("/")[-1]
            old_path = os.path.join(profile_images_dir, old_filename)
            if os.path.exists(old_path) and old_filename.startswith("profile_"):
                try:
                    os.remove(old_path)
                except:
                    pass
        
        # Atualiza URL no banco
        image_url = f"{config.PUBLIC_BASE_URL}/downloads/profile_images/{filename}"
        current_user.profile_image_url = image_url
        db.commit()
        
        return {"status": "uploaded", "url": image_url}
        
    except base64.binascii.Error:
        raise HTTPException(400, "Dados de imagem inválidos (não é base64 válido)")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Erro ao salvar imagem: {str(e)}")
