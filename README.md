# 🎵 Orfeu - High-Fidelity Streaming System

> "Uma descida ao submundo do P2P para resgatar a alta fidelidade sonora."

![Project Status](https://img.shields.io/badge/status-development-orange)
![License](https://img.shields.io/badge/license-MIT-blue)
![Python](https://img.shields.io/badge/backend-Python%20%7C%20FastAPI-yellow)
![Flutter](https://img.shields.io/badge/mobile-Flutter-02569B)

## 📖 Sobre o Projeto
O **Orfeu** é um sistema de streaming de áudio *self-hosted* focado em alta resolução (FLAC). Propõe uma arquitetura onde o usuário mantém diversidade de biblioteca e qualidade de mídia.

O sistema utiliza uma arquitetura cliente-servidor distribuída:
- **Core (Server-side):** Gerencia conexões P2P (Soulseek), transcodificação de áudio on-the-fly e metadados.
- **Client (Mobile):** Interface intuitiva para busca, reprodução e gestão de downloads offline.

## 🛠️ Tech Stack

### Backend (The Brain)
- **Linguagem:** Python 3.11+
- **Framework:** FastAPI
- **Database:** PostgreSQL
- **P2P Engine:** Slskd (Soulseek Client)
- **Audio Engine:** FFmpeg (Transcoding)

### Mobile (The Face)
- **Framework:** Flutter (Dart)
- **Audio:** just_audio
- **Local DB:** SQLite (Drift)

## ⚠️ Disclaimer & Ética
Este software foi desenvolvido estritamente para fins **educacionais e de pesquisa** sobre arquiteturas distribuídas e streaming de mídia.
O desenvolvedor não incentiva a pirataria. O uso da rede Soulseek e o download de materiais protegidos por direitos autorais são de inteira responsabilidade do usuário final.

## 🗺️ Roadmap
- [ ] Configuração do Ambiente Docker (Backend Base)
- [ ] Integração com API do Soulseek
- [ ] Streaming de Áudio Hi-Res (FLAC)
- [ ] App Mobile MVP (Busca e Play)
- [ ] Transcoding em Tempo Real (Quality Selector)
- [ ] Suporte Offline e Lyrics (Karaoke Mode)
- [ ] Recomendação via IA

## 📄 Licença
Distribuído sob a licença MIT. Veja `LICENSE` para mais informações.