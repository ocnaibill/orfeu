# **🎵 Orfeu \- Manual de Instalação e Uso**

Este guia descreve como configurar o ambiente de desenvolvimento para o projeto Orfeu (Player Hi-Res com Soulseek).

## **📋 Pré-requisitos**

* **Docker** e **Docker Compose** instalados na máquina.  
* Uma conta válida na rede **Soulseek** (Login e Senha).  
* Git.

## **⚙️ 1\. Configuração Inicial**

### **1.1 Variáveis de Ambiente**

O projeto utiliza um arquivo .env para gerenciar senhas e configurações sensíveis. Nunca suba este arquivo para o GitHub.

1. Na raiz do projeto, faça uma cópia do exemplo:  
   cp .env.example .env

   *(No Windows, apenas copie e renomeie o arquivo manualmente).*  
2. Edite o arquivo .env com um editor de texto e preencha:  
   * **POSTGRES\_USER/PASSWORD:** Defina uma senha para seu banco de dados local.  
   * **PUID/PGID:** Identificadores do seu usuário no Linux/Mac para evitar erros de permissão de arquivo.  
     * Para descobrir, rode o comando id no terminal. (Geralmente é 1000).  
   * **SLSKD\_SLSK\_USERNAME:** Seu usuário real do Soulseek.  
   * **SLSKD\_SLSK\_PASSWORD:** Sua senha real do Soulseek.  
   * **SLSKD\_API\_KEY:** **Deixe em branco por enquanto.** Vamos gerar isso no passo 3\.

## **🐳 2\. Rodando a Infraestrutura**

Com o arquivo .env salvo (mesmo sem a API Key), suba os containers pela primeira vez:

docker-compose up \-d \--build

Isso irá:

1. Baixar as imagens do PostgreSQL e Slskd.  
2. Construir a imagem do Backend Python (instalando dependências).  
3. Iniciar os serviços.

Verifique se tudo subiu corretamente:

docker ps

Você deve ver 3 containers rodando: orfeu\_backend, orfeu\_slskd e orfeu\_db.

## **🔑 3\. Configurando a Integração (Passo Crítico)**

Para o Backend (Python) conseguir comandar o Soulseek, precisamos de uma chave de segurança gerada pelo Slskd.

1. Acesse o painel do Slskd no navegador:  
   * **URL:** [http://localhost:5030](https://www.google.com/search?q=http://localhost:5030)  
   * **Login Padrão:** slskd  
   * Senha Padrão: slskd  
     (Se ele pedir login, use esses. Se ele já conectar na rede Soulseek, significa que suas credenciais do .env funcionaram).  
2. Vá em **Settings** (Ícone de Engrenagem ⚙️ no menu lateral) \-\> **Web API**.  
3. Na seção "Keys":  
   * Digite um nome (ex: OrfeuBackend).  
   * Clique no botão **\+ (Create)**.  
   * **COPIE O CÓDIGO GERADO IMEDIATAMENTE.** (Ele não será mostrado novamente).  
4. Volte ao seu arquivo .env na raiz do projeto e cole a chave:  
   SLSKD\_API\_KEY=ColeSuaChaveAquiSemAspas

5. Reinicie o Backend para ele ler a nova chave:  
   docker-compose restart backend

## **🚀 4\. Como Usar**

### **📄 Documentação da API (Swagger)**

O Backend gera documentação automática. Use isso para testar as rotas de busca e download.

* **URL:** [http://localhost:8000/docs](https://www.google.com/search?q=http://localhost:8000/docs)

**Teste Rápido:**

1. Vá em POST /search/{query} \-\> Try it out \-\> Digite uma banda \-\> Execute.  
2. Copie o search\_id retornado.  
3. Vá em GET /results/{search\_id} \-\> Cole o ID \-\> Execute.

### **💾 Monitorando Downloads**

Para ver o progresso dos downloads solicitados via API:

* **Painel Slskd:** [http://localhost:5030](https://www.google.com/search?q=http://localhost:5030) (Aba Downloads).  
* **Arquivos Físicos:** Os arquivos aparecerão na pasta downloads/ na raiz do seu projeto.

## **🛠️ Comandos Úteis**

\# Ver logs do Backend (útil para debugar erros de conexão)  
docker logs \-f orfeu\_backend

\# Ver logs do Soulseek  
docker logs \-f orfeu\_slskd

\# Parar tudo  
docker-compose down

\# Reconstruir (se você instalar novas libs no Python)  
docker-compose up \-d \--build

## **⚠️ Estrutura de Pastas Importante**

* backend/: Código fonte da API.  
* downloads/: Onde as músicas baixadas aparecem (Ignorado pelo Git).  
* slskd-config/: Configurações persistentes do Soulseek.