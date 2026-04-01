#!/bin/bash
###############################################################################
#  WireGuard - Installation et configuration automatique
#  Serveur Ubuntu sur Proxmox
#  Clients : admindamien, adminbetty
#
#  Usage :
#    git clone https://github.com/devcyberteck/wireguard.git
#    cd wireguard
#    sudo bash setup-wireguard.sh
###############################################################################
set -e

# ========================= CONFIGURATION ====================================
# Adresse VPN du serveur (tunnel)
SERVER_WG_IP="10.0.0.1"
SERVER_WG_SUBNET="24"
SERVER_PORT="51820"

# IP par laquelle les clients joindront le serveur (IP LAN Proxmox)
# Sera auto-detectee si laissee vide
SERVER_PUBLIC_IP=""

# Interface reseau principale (auto-detectee si vide)
SERVER_INTERFACE=""

# Clients : nom et IP VPN
CLIENTS=("admindamien" "adminbetty")
CLIENT_IPS=("10.0.0.2" "10.0.0.3")

# DNS utilise par les clients
CLIENT_DNS="1.1.1.1, 8.8.8.8"

# AllowedIPs pour les clients (0.0.0.0/0 = tout le trafic passe par le VPN)
CLIENT_ALLOWED_IPS="0.0.0.0/0, ::/0"
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

# Verification root
if [ "$EUID" -ne 0 ]; then
    error "Ce script doit etre execute en root (sudo bash setup-wireguard.sh)"
fi

# Auto-detection de l'interface reseau
if [ -z "$SERVER_INTERFACE" ]; then
    SERVER_INTERFACE=$(ip -o -4 route show default | awk '{print $5}' | head -1)
    if [ -z "$SERVER_INTERFACE" ]; then
        error "Impossible de detecter l'interface reseau. Renseignez SERVER_INTERFACE dans le script."
    fi
    info "Interface reseau detectee : $SERVER_INTERFACE"
fi

# Auto-detection de l'IP du serveur
if [ -z "$SERVER_PUBLIC_IP" ]; then
    SERVER_PUBLIC_IP=$(ip -4 addr show "$SERVER_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -z "$SERVER_PUBLIC_IP" ]; then
        error "Impossible de detecter l'IP du serveur. Renseignez SERVER_PUBLIC_IP dans le script."
    fi
    info "IP du serveur detectee : $SERVER_PUBLIC_IP"
fi

echo ""
echo "============================================="
echo "  WireGuard - Installation automatique"
echo "============================================="
echo "  Serveur VPN   : $SERVER_WG_IP/$SERVER_WG_SUBNET"
echo "  Port           : $SERVER_PORT"
echo "  IP publique    : $SERVER_PUBLIC_IP"
echo "  Interface      : $SERVER_INTERFACE"
echo "  Clients        : ${CLIENTS[*]}"
echo "============================================="
echo ""

# ========================= INSTALLATION =====================================
info "Mise a jour des paquets..."
apt update -y

info "Installation de WireGuard et outils..."
apt install -y wireguard qrencode

# ========================= IP FORWARDING ====================================
info "Activation du routage IP..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward.*=.*1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi
sysctl -p

# ========================= CLES SERVEUR =====================================
info "Generation des cles du serveur..."
cd /etc/wireguard
umask 077

if [ -f server_private.key ]; then
    warn "Les cles serveur existent deja, elles seront conservees."
else
    wg genkey | tee server_private.key | wg pubkey > server_public.key
fi

SERVER_PRIV=$(cat server_private.key)
SERVER_PUB=$(cat server_public.key)

# ========================= CLES ET CONFIGS CLIENTS ==========================
info "Generation des cles et configurations clients..."
mkdir -p /etc/wireguard/clients

for i in "${!CLIENTS[@]}"; do
    CLIENT="${CLIENTS[$i]}"
    CLIENT_IP="${CLIENT_IPS[$i]}"

    info "  -> Client : $CLIENT ($CLIENT_IP)"

    # Generation des cles client
    if [ -f "/etc/wireguard/clients/${CLIENT}_private.key" ]; then
        warn "    Les cles de $CLIENT existent deja, elles seront conservees."
    else
        wg genkey | tee "/etc/wireguard/clients/${CLIENT}_private.key" | \
            wg pubkey > "/etc/wireguard/clients/${CLIENT}_public.key"
    fi

    CLIENT_PRIV=$(cat "/etc/wireguard/clients/${CLIENT}_private.key")
    CLIENT_PUB=$(cat "/etc/wireguard/clients/${CLIENT}_public.key")

    # Creation du fichier de configuration client
    cat > "/etc/wireguard/clients/${CLIENT}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${CLIENT_IP}/32
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = ${CLIENT_ALLOWED_IPS}
PersistentKeepalive = 25
EOF

    chmod 600 "/etc/wireguard/clients/${CLIENT}.conf"
done

# ========================= CONFIG SERVEUR ===================================
info "Creation de la configuration serveur wg0..."

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${SERVER_PRIV}
Address = ${SERVER_WG_IP}/${SERVER_WG_SUBNET}
ListenPort = ${SERVER_PORT}

# NAT et forwarding
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_INTERFACE} -j MASQUERADE
EOF

# Ajout des peers (clients) a la config serveur
for i in "${!CLIENTS[@]}"; do
    CLIENT="${CLIENTS[$i]}"
    CLIENT_IP="${CLIENT_IPS[$i]}"
    CLIENT_PUB=$(cat "/etc/wireguard/clients/${CLIENT}_public.key")

    cat >> /etc/wireguard/wg0.conf <<EOF

# ${CLIENT}
[Peer]
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_IP}/32
EOF
done

chmod 600 /etc/wireguard/wg0.conf

# ========================= DEMARRAGE ========================================
info "Activation et demarrage de WireGuard..."

# Arreter si deja en cours
systemctl stop wg-quick@wg0 2>/dev/null || true

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# ========================= VERIFICATION =====================================
echo ""
echo "============================================="
echo "  WireGuard est actif !"
echo "============================================="
echo ""
wg show
echo ""

# ========================= AFFICHAGE DES CONFIGS CLIENTS ====================
echo "============================================="
echo "  CONFIGURATIONS CLIENTS"
echo "============================================="
echo ""
echo "Les fichiers sont dans : /etc/wireguard/clients/"
echo ""

for CLIENT in "${CLIENTS[@]}"; do
    echo "---------------------------------------------"
    echo "  $CLIENT"
    echo "---------------------------------------------"
    cat "/etc/wireguard/clients/${CLIENT}.conf"
    echo ""

    # QR Code pour import facile sur mobile
    echo "  QR Code (scanner avec l'app WireGuard mobile) :"
    echo ""
    qrencode -t ansiutf8 < "/etc/wireguard/clients/${CLIENT}.conf"
    echo ""
done

echo "============================================="
echo "  RESUME"
echo "============================================="
echo ""
echo "  Serveur WireGuard   : $SERVER_WG_IP:$SERVER_PORT"
echo "  Cle publique serveur: $SERVER_PUB"
echo ""
echo "  Pour importer la config sur un client :"
echo "    1. Installer WireGuard sur le client"
echo "    2. Scanner le QR code ci-dessus"
echo "    OU"
echo "    3. Copier le fichier .conf depuis /etc/wireguard/clients/"
echo ""
echo "  Fichiers generes :"
echo "    /etc/wireguard/wg0.conf                         (serveur)"
for CLIENT in "${CLIENTS[@]}"; do
    echo "    /etc/wireguard/clients/${CLIENT}.conf   (client)"
done
echo ""
info "Installation terminee !"
