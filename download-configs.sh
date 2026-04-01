#!/bin/bash
###############################################################################
#  Telechargement des configs WireGuard via ngrok
#
#  Usage :
#    sudo bash download-configs.sh              (lance le serveur + ngrok)
#    sudo bash download-configs.sh YOUR_TOKEN   (configure le token ngrok)
#
#  Prerequis : un compte gratuit sur https://ngrok.com
###############################################################################

PORT=8080
CONFIGS_DIR="/etc/wireguard/clients"
NGROK_TOKEN="3BlBRsrRFB6ZIKZVcF5QUQyIboJ_7yiJeSr6mW9JkEt3esJEu"

# Verification root
if [ "$EUID" -ne 0 ]; then
    echo "[ERREUR] Ce script doit etre execute en root (sudo bash download-configs.sh)"
    exit 1
fi

# Verification que les configs existent
if [ ! -d "$CONFIGS_DIR" ]; then
    echo "[ERREUR] Aucune config client trouvee. Lancez d'abord setup-wireguard.sh"
    exit 1
fi

# ========================= INSTALLATION NGROK ===============================
if ! command -v ngrok &>/dev/null; then
    echo "[INFO] Installation de ngrok via apt..."
    curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list
    apt update -y
    apt install -y ngrok
    if ! command -v ngrok &>/dev/null; then
        echo "[ERREUR] Installation de ngrok echouee."
        exit 1
    fi
    echo "[INFO] ngrok installe."
fi

# ========================= TOKEN NGROK ======================================
echo "[INFO] Configuration du token ngrok..."
ngrok config add-authtoken "$NGROK_TOKEN"

# ========================= PREPARATION FICHIERS =============================
TMPDIR=$(mktemp -d)

cp "$CONFIGS_DIR"/*.conf "$TMPDIR/"

cat > "$TMPDIR/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>WireGuard - Configs</title>
    <style>
        body { font-family: Arial; max-width: 600px; margin: 50px auto; background: #1a1a2e; color: #eee; }
        h1 { color: #e94560; }
        a { display: block; margin: 20px 0; padding: 20px; background: #16213e;
            text-decoration: none; border-radius: 8px; font-size: 1.2em; color: #e94560; }
        a:hover { background: #0f3460; color: #fff; }
        .warn { color: #f5a623; font-size: 0.9em; margin-top: 40px; }
    </style>
</head>
<body>
    <h1>WireGuard Configs</h1>
    <p>Cliquez pour telecharger :</p>
    <a href="admindamien.conf">admindamien.conf (Damien)</a>
    <a href="adminbetty.conf">adminbetty.conf (Betty)</a>
    <p class="warn">Fermez ce serveur apres telechargement (Ctrl+C dans le terminal).<br>
    Ces fichiers contiennent des cles privees !</p>
</body>
</html>
HTMLEOF

# ========================= LANCEMENT ========================================
# Demarrer le serveur HTTP en arriere-plan
cd "$TMPDIR"
python3 -m http.server $PORT --bind 127.0.0.1 &
HTTP_PID=$!

# Demarrer ngrok en arriere-plan
ngrok http $PORT --log=stdout > /tmp/ngrok.log 2>&1 &
NGROK_PID=$!

# Attendre que ngrok demarre
sleep 3

# Recuperer l'URL publique ngrok
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oP '"public_url"\s*:\s*"\K[^"]+' | head -1)

echo ""
echo "============================================="
echo "  SERVEUR PRET !"
echo "============================================="
echo ""

if [ -n "$NGROK_URL" ]; then
    echo "  Ouvre cette URL dans ton navigateur :"
    echo ""
    echo "  $NGROK_URL"
    echo ""
else
    echo "  [WARN] Impossible de recuperer l'URL ngrok."
    echo "  Verifie dans /tmp/ngrok.log"
    echo "  Ou va sur http://127.0.0.1:4040 depuis le serveur."
    echo ""
fi

echo "  Fichiers disponibles :"
echo "    - admindamien.conf  (Damien)"
echo "    - adminbetty.conf   (Betty)"
echo ""
echo "  Ctrl+C pour arreter le serveur"
echo "============================================="
echo ""

# Attendre Ctrl+C
cleanup() {
    echo ""
    echo "[INFO] Arret du serveur..."
    kill $HTTP_PID 2>/dev/null
    kill $NGROK_PID 2>/dev/null
    rm -rf "$TMPDIR"
    echo "[INFO] Serveur arrete, fichiers temporaires supprimes."
    exit 0
}

trap cleanup INT TERM

# Garder le script actif
wait $NGROK_PID
