#!/bin/bash

# ==============================================================================
# WiFiCyberTools v1.0 - Suite complète de cybersécurité WiFi
# ==============================================================================

set -euo pipefail

# Configuration
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VERSION="1.0"
export CONFIG_FILE="$SCRIPT_DIR/config/settings.conf"
export LOG_DIR="$SCRIPT_DIR/logs"
export DATA_DIR="$SCRIPT_DIR/data"

# Chargement de la configuration
source "$CONFIG_FILE" 2>/dev/null || {
    echo "❌ Fichier de configuration manquant. Exécutez: ./install.sh"
    exit 1
}

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Fonctions utilitaires
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_DIR/cybertools.log"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_DIR/cybertools.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/cybertools.log"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_DIR/cybertools.log"
}

header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                       ${BOLD}WiFiCyberTools v$VERSION${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                   Suite complète cybersécurité WiFi                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Chargement des modules
load_module() {
    local module="$1"
    local module_path="$SCRIPT_DIR/modules/${module}.sh"
    
    if [ -f "$module_path" ]; then
        source "$module_path"
    else
        error "Module $module non trouvé: $module_path"
        exit 1
    fi
}

# Status système
show_status() {
    header
    echo -e "${BLUE}📊 STATUS SYSTÈME${NC}"
    echo
    
    # Status des outils
    local tools=("hashcat" "hcxpcapngtool" "aircrack-ng" "tshark" "ssh" "rsync")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "  ✅ $tool: ${GREEN}Installé${NC}"
        else
            echo -e "  ❌ $tool: ${RED}Manquant${NC}"
        fi
    done
    
    echo
    
    # Status GPU
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo -e "${BLUE}🖥️  GPU NVIDIA${NC}"
        nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader | while read line; do
            echo "  🔥 $line"
        done
    else
        echo -e "  ⚠️  Aucun GPU NVIDIA détecté"
    fi
    
    echo
    
    # Status des données
    local pcap_count=$(find "$DATA_DIR/captures" -name "*.pcap*" 2>/dev/null | wc -l)
    local converted_count=$(find "$DATA_DIR/converted" -name "*.hc22000" 2>/dev/null | wc -l)
    local wordlist_count=$(find "$DATA_DIR/wordlists" -name "*.txt" 2>/dev/null | wc -l)
    
    echo -e "${BLUE}📁 DONNÉES${NC}"
    echo "  📦 Captures PCAP: $pcap_count"
    echo "  🔄 Fichiers convertis: $converted_count"
    echo "  📚 Wordlists: $wordlist_count"
    
    # Status Pwnagotchi
    echo
    echo -e "${BLUE}🤖 PWNAGOTCHI${NC}"
    if ping -c 1 -W 2 "$PWNAGOTCHI_IP" >/dev/null 2>&1; then
        echo -e "  ✅ Pwnagotchi: ${GREEN}Accessible ($PWNAGOTCHI_IP)${NC}"
        
        # Test SSH
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=3 -o BatchMode=yes \
           "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" exit 2>/dev/null; then
            echo -e "  🔑 SSH: ${GREEN}Clé configurée${NC}"
        else
            echo -e "  🔑 SSH: ${YELLOW}Clé à configurer${NC}"
        fi
    else
        echo -e "  ❌ Pwnagotchi: ${RED}Non accessible${NC}"
    fi
}

# Menu principal
main_menu() {
    while true; do
        show_status
        echo
        echo -e "${CYAN}┌─ MENU PRINCIPAL ───────────────────────────────────────────────────────────┐${NC}"
        echo "   1) 🛠️  Installation et configuration"
        echo "   2) 🔑 Gestion des clés SSH"
        echo "   3) 🔍 Vérification des fichiers PCAP"
        echo "   4) 📥 Synchronisation Pwnagotchi"
        echo "   5) ✅ Validation des handshakes"
        echo "   6) 🧹 Nettoyage des captures"
        echo "   7) 💥 Attaques Hashcat"
        echo "   8) 📚 Gestion des wordlists"
        echo "   9) 📊 Visualisation des résultats"
        echo "   0) ❌ Quitter"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
        read -p "Votre choix [0-9]: " choice
        
        case $choice in
            1) module_installer ;;
            2) module_ssh_manager ;;
            3) module_pcap_checker ;;
            4) module_pwnagotchi_sync ;;
            5) module_handshake_validator ;;
            6) module_pcap_cleaner ;;
            7) module_hashcat_runner ;;
            8) module_wordlist_manager ;;
            9) module_results_viewer ;;
            0) 
                success "Au revoir!"
                exit 0
                ;;
            *) 
                error "Option invalide: $choice"
                sleep 2
                ;;
        esac
    done
}

# Chargement des modules
module_installer() {
    load_module "installer"
    installer_menu
}

module_ssh_manager() {
    load_module "ssh_manager"
    ssh_manager_menu
}

module_pcap_checker() {
    load_module "pcap_checker"
    pcap_checker_menu
}

module_pwnagotchi_sync() {
    load_module "pwnagotchi_sync"
    pwnagotchi_sync_menu
}

module_handshake_validator() {
    load_module "handshake_validator"
    handshake_validator_menu
}

module_pcap_cleaner() {
    load_module "pcap_cleaner"
    pcap_cleaner_menu
}

module_hashcat_runner() {
    load_module "hashcat_runner"
    hashcat_runner_menu
}

module_wordlist_manager() {
    load_module "wordlist_manager"
    wordlist_manager_menu
}

module_results_viewer() {
    load_module "results_viewer"
    results_viewer_menu
}

# Gestion des signaux
cleanup() {
    echo
    warn "Interruption détectée, nettoyage en cours..."
    pkill -f hashcat 2>/dev/null || true
    exit 130
}

trap cleanup INT TERM

# Point d'entrée principal
main() {
    # Vérifications de base
    if [ ! -d "$SCRIPT_DIR/modules" ]; then
        error "Dossier modules manquant. Exécutez: ./install.sh"
        exit 1
    fi
    
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    log "Démarrage WiFiCyberTools v$VERSION"
    
    # Arguments en ligne de commande
    case "${1:-}" in
        --install)
            load_module "installer"
            install_requirements
            ;;
        --sync)
            load_module "pwnagotchi_sync"
            auto_sync
            ;;
        --attack)
            if [ -z "${2:-}" ]; then
                error "Usage: $0 --attack <file.hc22000>"
                exit 1
            fi
            load_module "hashcat_runner"
            run_attack "$2"
            ;;
        --clean)
            load_module "pcap_cleaner"
            auto_clean
            ;;
        --help)
            echo "WiFiCyberTools v$VERSION"
            echo "Usage: $0 [options]"
            echo "  --install  : Installation automatique"
            echo "  --sync     : Synchronisation Pwnagotchi"
            echo "  --attack <file> : Attaque directe"
            echo "  --clean    : Nettoyage automatique"
            echo "  --help     : Aide"
            ;;
        "")
            main_menu
            ;;
        *)
            error "Option inconnue: $1"
            exit 1
            ;;
    esac
}

main "$@"
