#!/bin/bash
###############################################################################
#  Upload des configs WireGuard sur file.io pour telechargement externe
#  Les fichiers sont supprimes automatiquement apres le 1er telechargement
#
#  Usage : sudo bash download-configs.sh
#  Puis recopiez les URLs affichees dans votre navigateur
###############################################################################

# Verification root
if [ "$EUID" -ne 0 ]; then
    echo "[ERREUR] Ce script doit etre execute en root (sudo bash download-configs.sh)"
    exit 1
fi

# Verification que les configs existent
if [ ! -d /etc/wireguard/clients ]; then
    echo "[ERREUR] Aucune config client trouvee. Lancez d'abord setup-wireguard.sh"
    exit 1
fi

# Installer curl si absent
if ! command -v curl &>/dev/null; then
    apt install -y curl
fi

echo ""
echo "============================================="
echo "  Upload des configs WireGuard"
echo "============================================="
echo ""

for CONF in /etc/wireguard/clients/*.conf; do
    NAME=$(basename "$CONF")
    echo "[...] Upload de $NAME ..."

    RESPONSE=$(curl -s -F "file=@${CONF}" https://file.io)
    URL=$(echo "$RESPONSE" | grep -oP '"link"\s*:\s*"\K[^"]+')

    if [ -n "$URL" ]; then
        echo ""
        echo "=========================================="
        echo "  $NAME"
        echo "  $URL"
        echo "=========================================="
        echo ""
    else
        echo "[ERREUR] Echec upload de $NAME"
        echo "  Reponse: $RESPONSE"
        echo ""
        echo "  Tentative avec transfer.sh ..."
        URL=$(curl -s --upload-file "$CONF" "https://transfer.sh/${NAME}")
        if [ -n "$URL" ]; then
            echo ""
            echo "=========================================="
            echo "  $NAME"
            echo "  $URL"
            echo "=========================================="
            echo ""
        else
            echo "[ERREUR] Echec des 2 services. Affichage du contenu :"
            echo "-----"
            cat "$CONF"
            echo "-----"
        fi
    fi
done

echo ""
echo "============================================="
echo "  INSTRUCTIONS"
echo "============================================="
echo ""
echo "  1. Recopiez les URLs ci-dessus dans votre navigateur"
echo "  2. Le fichier se telecharge automatiquement"
echo "  3. Importez le .conf dans l'app WireGuard du client"
echo ""
echo "  ATTENTION : chaque lien ne fonctionne qu'UNE SEULE FOIS"
echo "  Relancez ce script si vous avez besoin d'un nouveau lien"
echo ""
echo "============================================="
