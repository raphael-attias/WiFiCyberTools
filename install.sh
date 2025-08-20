#!/bin/bash
# ==============================================================================
# Installation WiFiCyberTools v1.0
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Fonctions log
log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
success(){ echo -e "${CYAN}[SUCCESS]${NC} $1"; }

header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} Installation WiFiCyberTools v1.0 ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

create_directories() {
    log "Création de la structure de répertoires..."

    local dirs=(
        "$SCRIPT_DIR/config"
        "$SCRIPT_DIR/modules"
        "$SCRIPT_DIR/data/captures"
        "$SCRIPT_DIR/data/converted"
        "$SCRIPT_DIR/data/wordlists"
        "$SCRIPT_DIR/data/results"
        "$SCRIPT_DIR/logs"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "Créé: $dir"
    done
}

create_config() {
    log "Création des fichiers de configuration..."

    # Configuration principale
    cat > "$SCRIPT_DIR/config/settings.conf" << 'EOF'
# Configuration WiFiCyberTools
PWNAGOTCHI_IP="10.0.0.2"
PWNAGOTCHI_USER="pi"
PWNAGOTCHI_PASS="raspberry"
PWNAGOTCHI_HANDSHAKE_DIR="/home/pi/handshakes"

# SSH
SSH_KEY_PATH="$HOME/.ssh/pwnagotchi_rsa"

# Répertoires
DATA_DIR="./data"
CAPTURES_DIR="$DATA_DIR/captures"
CONVERTED_DIR="$DATA_DIR/converted"
WORDLISTS_DIR="$DATA_DIR/wordlists"
RESULTS_DIR="$DATA_DIR/results"

# Hashcat
HASHCAT_WORKLOAD=3
HASHCAT_TIMEOUT=3600
GPU_TEMP_LIMIT=85

# Nettoyage
MIN_HANDSHAKE_PACKETS=2
KEEP_EMPTY_PCAP=false
AUTO_BACKUP=true
EOF

    # Configuration wordlists
    cat > "$SCRIPT_DIR/config/wordlists.conf" << 'EOF'
# URLs des wordlists populaires
ROCKYOU_URL="https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt"
PROBABLE_V2_URL="https://github.com/berzerk0/Probable-Wordlists/raw/master/Real-Passwords/Top-12Million-probable-v2.txt"

# Wordlists WiFi spécialisées
WIFI_WPA_URL="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/WiFi-WPA/probable-v2-wpa-top4800.txt"
DARKWEB_URL="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Leaked-Databases/darkweb2017-top10000.txt"

# Wordlists par langue
FRENCH_URL="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Leaked-Databases/french-password-list.txt"
ENGLISH_URL="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Common-Credentials/10-million-password-list-top-1000000.txt"
EOF
}

# (⚠️ je n’ai pas tout recopié ici, mais tu peux conserver ton gros bloc "create_modules" et les modules .sh → ils fonctionnent si tu enlèves juste les `text` inutiles)

create_readme() {
    cat > "$SCRIPT_DIR/README.md" << 'EOF'
# WiFiCyberTools v1.0
Suite complète d'outils de cybersécurité WiFi pour laboratoires et tests de pénétration.

## Installation
git clone <repository>
cd WiFiCyberTools
sudo ./install.sh

## Utilisation
### Interface interactive
./cybertools.sh

### Commandes directes
./cybertools.sh --sync       # Synchronisation Pwnagotchi
./cybertools.sh --attack file.hc22000   # Attaque directe
./cybertools.sh --clean      # Nettoyage automatique
EOF
}

make_executable() {
    chmod +x "$SCRIPT_DIR/cybertools.sh"
    chmod +x "$SCRIPT_DIR/install.sh"
    chmod +x "$SCRIPT_DIR/modules"/*.sh 2>/dev/null || true
}

main() {
    header
    log "Installation de WiFiCyberTools dans: $SCRIPT_DIR"

    create_directories
    create_config
    create_modules
    create_readme
    make_executable

    echo
    success "Installation terminée avec succès!"
    echo
    echo "Prochaines étapes:"
    echo "1. sudo ./cybertools.sh --install   (installation des outils)"
    echo "2. ./cybertools.sh                  (lancement de l'interface)"
    echo
    echo "Documentation: README.md"
}

main "$@"
