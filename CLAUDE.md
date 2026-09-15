# Vitta Sistemas — Contexto do Projeto

## Stack
- **Frontend**: HTML puro + Tailwind CSS (CDN) + JavaScript vanilla
- **Backend**: Supabase (project ID: `ccdeuabmjwgntwssjfgo`)
- **Hospedagem web**: Hostinger via FTP (subir `index.html`, `pages/`, `assets/`, `img/`, `mobile/`)
- **Node.js**: instalado via nvm (v24.16.0)

## Estrutura
```
index.html               → Login
pages/
  dashboard.html         → Dashboard principal
  empresas.html          → Gestão de empresas (Admin Global)
  usuarios.html          → Usuários admin (Admin Global + Admin Empresa)
  usuarios-empresa.html  → Usuários da empresa
  profissionais.html     → Cadastro de profissionais
  pacientes.html         → Cadastro de pacientes
  redefinir-senha.html   → Troca de senha (normal e obrigatória)
  ...
assets/js/
  config.js              → URL e chave do Supabase + APP_BASE_URL
  notifications.js       → Sistema de notificações
```

## Autenticação
- `ADMIN_GLOBAL` → acesso total (empresas, usuários admin)
- `ADMIN_EMPRESA` → acesso à empresa vinculada
- `SECRETARIA`, `PROFISSIONAL` → acesso restrito
- Novo usuário criado → `force_password_change: true` via RPC `set_force_password_change`
- Login detecta flag e redireciona para `redefinir-senha.html?mode=force`

## RPCs criadas no Supabase
- `set_force_password_change(p_email text)` → seta flag de troca obrigatória de senha
- `delete_profissional(p_id uuid)` → exclui profissional + desvincula usuário
- `delete_usuario_empresa(p_id uuid, p_auth_id uuid)` → exclui usuário da tabela e do auth
- `create_usuario_admin(...)` → cria usuário admin (já existia)
- `create_usuario_empresa(...)` → cria usuário da empresa (já existia)
- `update_usuario_password(...)` → altera senha (já existia)

## App Mobile (Capacitor)
- **App ID**: `com.vittasistemas.app`
- **Estratégia**: Opção B — app carrega URL hospedada (não bundled)
- **Config**: `capacitor.config.json` na raiz do projeto
- **Plataformas**: iOS publicado na App Store; Android ainda em teste local
- **App iOS**: "Vitta Sistemas" aprovado e disponível em https://apps.apple.com/app/vitta-sistemas/id6780993167 (aprovação recebida em 15/07/2026)
- **Celular de teste**: Xiaomi 22101316UG — Android 14 — conectado via Wi-Fi
- **IP do Mac na rede local**: `192.168.3.92`

### Servidores de teste (desenvolvimento)
- ❌ Live Server (porta 5500) — causa auto-reload que limpa campos do formulário
- ✅ Python HTTP Server (porta 8080) — usar este para testes no celular
  ```bash
  cd "caminho/do/projeto"
  python3 -m http.server 8080
  ```
- `capacitor.config.json` apontando para: `http://192.168.3.92:8080`

### Para rodar o app no celular
1. Iniciar servidor Python no terminal do VS Code:
   ```bash
   python3 -m http.server 8080
   ```
2. Celular Xiaomi conectado via Wi-Fi (Depuração sem fio ativada)
3. No Android Studio → clicar ▶ Run

### Para produção (quando hospedar na Hostinger)
1. Subir `index.html`, `pages/`, `assets/`, `img/` via FTP (igual hoje)
2. Atualizar `capacitor.config.json`:
   ```json
   "server": { "url": "https://seudominio.com.br" }
   ```
3. Rodar `npx cap sync android`
4. Gerar APK assinado no Android Studio
5. Publicar na Play Store

## Pendências Mobile
- [x] Instalar Xcode completo
- [x] Criar conta no Apple Developer Program ($99/ano)
- [x] Enviar e aprovar o app iOS na App Store (aprovado em 15/07/2026)
- [ ] Melhorar responsividade das telas para mobile
- [x] Configurar ícone e splash screen do app (confirmado em 24/07/2026: `AppIcon.appiconset`/`Splash.imageset` no iOS e mipmaps/`splash.png` no Android já customizados)
- [ ] Hospedar sistema na Hostinger com domínio
- [ ] Atualizar `server.url` para URL de produção
- [ ] Gerar APK assinado e publicar na Play Store
- [ ] Criar conta no Google Play Console (taxa única de $25)

## Comandos úteis
```bash
# Ativar Node (nvm) — sempre necessário antes dos comandos npx
export NVM_DIR="$HOME/.nvm" && source "$NVM_DIR/nvm.sh"

# Servidor de teste sem auto-reload (usar no celular)
python3 -m http.server 8080

# Sincronizar app com nova configuração
npx cap sync android
npx cap sync ios

# Abrir projetos nativos
npx cap open android
npx cap open ios
```

## Como continuar
1. Abra o VS Code na pasta do projeto
2. Abra o Claude Code
3. Diga: **"continue o projeto Vitta Sistemas"** — eu lerei este arquivo automaticamente
