#!/bin/bash
# Inicia o servidor de desenvolvimento para testes no celular
# Uso: ./serve.sh
# Copia os arquivos fonte para www/ e sincroniza com o app Android antes de iniciar

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Sincronizando arquivos para www/..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
rsync -a --exclude='*.DS_Store' pages/  www/pages/
rsync -a --exclude='*.DS_Store' assets/ www/assets/
rsync -a --exclude='*.DS_Store' img/    www/img/
cp index.html www/index.html
echo " ✓ Arquivos copiados para www/"

echo " Executando cap sync android..."
npx cap sync android 2>/dev/null && echo " ✓ cap sync concluído" || echo " ⚠ cap sync falhou (verifique o Android Studio)"
echo ""

# Detecta o IP da rede local automaticamente
IP=$(ifconfig | grep "inet 192" | awk '{print $2}' | head -1)
if [ -z "$IP" ]; then
  IP="localhost"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Vitta Sistemas — Servidor de Teste"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " URL: http://$IP:8080"
echo " Ctrl+C para parar"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const mime = {
  'html':'text/html','js':'application/javascript','css':'text/css',
  'png':'image/png','jpg':'image/jpeg','jpeg':'image/jpeg',
  'ico':'image/x-icon','json':'application/json','svg':'image/svg+xml'
};
const root = process.cwd();
const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin','*');
  let url = req.url.split('?')[0];
  if(url === '/') url = '/index.html';
  const file = path.join(root, url);
  if(!file.startsWith(root)){res.writeHead(403);res.end();return;}
  fs.readFile(file, (err, data) => {
    if(err){res.writeHead(404);res.end('Not found');return;}
    const ext = path.extname(file).slice(1).toLowerCase();
    res.writeHead(200,{'Content-Type':mime[ext]||'text/plain'});
    res.end(data);
  });
});
server.listen(8080,'0.0.0.0');
"
