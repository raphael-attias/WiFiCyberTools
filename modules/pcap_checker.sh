#!/bin/bash

# ==============================================================================
# Module de vérification PCAP WiFiCyberTools
# ==============================================================================

pcap_checker_menu() {
    header
    echo -e "${BLUE}🔍 VÉRIFICATION DES FICHIERS PCAP${NC}"
    
    local pcap_count=$(find "$CAPTURES_DIR" -name "*.pcap*" 2>/dev/null | wc -l)
    echo -e "  📁 Fichiers PCAP disponibles: ${GREEN}$pcap_count${NC}"
    
    echo
    echo "1) Vérification complète des fichiers PCAP"
    echo "2) Analyse rapide de l'intégrité"
    echo "3) Détection des protocoles WiFi"
    echo "4) Vérification de la structure des paquets"
    echo "5) Analyse des métadonnées"
    echo "6) Rapport détaillé des fichiers"
    echo "7) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-7]: " choice
    
    case $choice in
        1) verify_all_pcap ;;
        2) quick_integrity_check ;;
        3) detect_wifi_protocols ;;
        4) check_packet_structure ;;
        5) analyze_metadata ;;
        6) generate_detailed_report ;;
        7) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    pcap_checker_menu
}

verify_all_pcap() {
    header
    log "Vérification complète des fichiers PCAP..."
    
    if [ ! -d "$CAPTURES_DIR" ]; then
        error "Répertoire captures non trouvé: $CAPTURES_DIR"
        return 1
    fi
    
    local pcap_files=($(find "$CAPTURES_DIR" -name "*.pcap*" -type f))
    local total=${#pcap_files[@]}
    
    if [ "$total" -eq 0 ]; then
        warn "Aucun fichier PCAP trouvé"
        return 1
    fi
    
    log "Analyse de $total fichier(s)..."
    
    local valid_count=0
    local invalid_count=0
    local current=0
    
    for pcap_file in "${pcap_files[@]}"; do
        current=$((current + 1))
        local filename=$(basename "$pcap_file")
        
        printf "\r[%d/%d] Vérification: %s" "$current" "$total" "$filename"
        
        # Test avec tshark
        if timeout 10 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
            # Test structure WiFi
            local wifi_packets=$(timeout 10 tshark -r "$pcap_file" -Y "wlan" -T fields -e frame.number 2>/dev/null | wc -l)
            
            if [ "$wifi_packets" -gt 0 ]; then
                valid_count=$((valid_count + 1))
                echo "✓" > "/tmp/pcap_${filename}.status"
                echo "WiFi packets: $wifi_packets" > "/tmp/pcap_${filename}.info"
            else
                echo "○" > "/tmp/pcap_${filename}.status"
                echo "No WiFi packets detected" > "/tmp/pcap_${filename}.info"
            fi
        else
            invalid_count=$((invalid_count + 1))
            echo "✗" > "/tmp/pcap_${filename}.status"
            echo "Corrupted or unreadable file" > "/tmp/pcap_${filename}.info"
        fi
    done
    
    echo
    echo
    success "Vérification terminée:"
    echo "  ✅ Fichiers valides: $valid_count"
    echo "  ❌ Fichiers invalides: $invalid_count"
    echo "  📊 Total vérifié: $total"
}

quick_integrity_check() {
    header
    log "Vérification rapide de l'intégrité..."
    
    local pcap_files=($(find "$CAPTURES_DIR" -name "*.pcap*" -type f))
    local total=${#pcap_files[@]}
    local corrupted=0
    
    for pcap_file in "${pcap_files[@]}"; do
        local filename=$(basename "$pcap_file")
        
        # Test rapide avec file
        if ! file "$pcap_file" | grep -q "pcap"; then
            corrupted=$((corrupted + 1))
            warn "Fichier suspect: $filename"
        fi
    done
    
    if [ "$corrupted" -eq 0 ]; then
        success "Tous les fichiers semblent intègres"
    else
        warn "$corrupted fichier(s) potentiellement corrompu(s)"
    fi
}

detect_wifi_protocols() {
    header
    log "Détection des protocoles WiFi..."
    
    local pcap_files=($(find "$CAPTURES_DIR" -name "*.pcap*" -type f | head -5))
    
    for pcap_file in "${pcap_files[@]}"; do
        local filename=$(basename "$pcap_file")
        echo -e "${CYAN}Analyse: $filename${NC}"
        
        # Détection des types de paquets
        local beacon_count=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.fc.type_subtype == 8" -T fields -e frame.number 2>/dev/null | wc -l)
        local probe_count=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.fc.type_subtype == 4" -T fields -e frame.number 2>/dev/null | wc -l)
        local auth_count=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.fc.type_subtype == 11" -T fields -e frame.number 2>/dev/null | wc -l)
        local eapol_count=$(timeout 15 tshark -r "$pcap_file" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l)
        
        echo "  📡 Beacons: $beacon_count"
        echo "  🔍 Probe Requests: $probe_count"
        echo "  🔐 Auth frames: $auth_count"
        echo "  🤝 EAPOL packets: $eapol_count"
        
        # Détection des réseaux
        local networks=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.fc.type_subtype == 8" -T fields -e wlan.ssid 2>/dev/null | grep -v "^$" | sort -u | head -3)
        if [ -n "$networks" ]; then
            echo "  📶 Réseaux détectés:"
            echo "$networks" | while read -r ssid; do
                echo "    - $ssid"
            done
        fi
        echo
    done
}

check_packet_structure() {
    header
    log "Vérification de la structure des paquets..."
    
    local sample_file=$(find "$CAPTURES_DIR" -name "*.pcap*" -type f | head -1)
    
    if [ -z "$sample_file" ]; then
        warn "Aucun fichier PCAP disponible"
        return 1
    fi
    
    local filename=$(basename "$sample_file")
    echo -e "${CYAN}Analyse détaillée: $filename${NC}"
    
    # Statistiques générales
    local total_packets=$(timeout 20 tshark -r "$sample_file" -T fields -e frame.number 2>/dev/null | wc -l)
    local file_size=$(stat -f%z "$sample_file" 2>/dev/null || stat -c%s "$sample_file" 2>/dev/null)
    local duration=$(timeout 20 tshark -r "$sample_file" -T fields -e frame.time_relative 2>/dev/null | tail -1)
    
    echo "  📊 Paquets total: $total_packets"
    echo "  💾 Taille fichier: $((file_size / 1024)) KB"
    echo "  ⏱️  Durée capture: ${duration:-"Inconnue"} secondes"
    
    # Types de frames WiFi
    echo
    echo "  📋 Types de frames WiFi:"
    local management=$(timeout 15 tshark -r "$sample_file" -Y "wlan.fc.type == 0" -T fields -e frame.number 2>/dev/null | wc -l)
    local control=$(timeout 15 tshark -r "$sample_file" -Y "wlan.fc.type == 1" -T fields -e frame.number 2>/dev/null | wc -l)
    local data=$(timeout 15 tshark -r "$sample_file" -Y "wlan.fc.type == 2" -T fields -e frame.number 2>/dev/null | wc -l)
    
    echo "    Management: $management"
    echo "    Control: $control"
    echo "    Data: $data"
}

analyze_metadata() {
    header
    log "Analyse des métadonnées..."
    
    local pcap_files=($(find "$CAPTURES_DIR" -name "*.pcap*" -type f))
    
    echo -e "${CYAN}Métadonnées des fichiers PCAP:${NC}"
    echo
    
    for pcap_file in "${pcap_files[@]}"; do
        local filename=$(basename "$pcap_file")
        local size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
        local date=$(stat -f%Sm "$pcap_file" 2>/dev/null || stat -c%y "$pcap_file" 2>/dev/null | cut -d' ' -f1)
        local permissions=$(stat -f%Sp "$pcap_file" 2>/dev/null || stat -c%A "$pcap_file" 2>/dev/null)
        
        echo "📁 $filename"
        echo "  📅 Date: $date"
        echo "  💾 Taille: $((size / 1024)) KB"
        echo "  🔒 Permissions: $permissions"
        
        # Essayer d'extraire info du nom de fichier
        if [[ "$filename" =~ _([a-fA-F0-9]{12})\.pcap ]]; then
            local bssid="${BASH_REMATCH[1]}"
            echo "  📶 BSSID probable: ${bssid:0:2}:${bssid:2:2}:${bssid:4:2}:${bssid:6:2}:${bssid:8:2}:${bssid:10:2}"
        fi
        echo
    done
}

generate_detailed_report() {
    header
    log "Génération du rapport détaillé..."
    
    local report_file="$LOG_DIR/pcap_analysis_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=============================================================================="
        echo "                    RAPPORT D'ANALYSE PCAP - WiFiCyberTools"
        echo "=============================================================================="
        echo "Date: $(date)"
        echo "Répertoire analysé: $CAPTURES_DIR"
        echo
        
        echo "=== STATISTIQUES GLOBALES ==="
        local total_files=$(find "$CAPTURES_DIR" -name "*.pcap*" | wc -l)
        local total_size=$(du -sh "$CAPTURES_DIR" 2>/dev/null | cut -f1)
        
        echo "Fichiers PCAP total: $total_files"
        echo "Taille totale: $total_size"
        echo
        
        echo "=== ANALYSE PAR FICHIER ==="
        find "$CAPTURES_DIR" -name "*.pcap*" -type f | while IFS= read -r pcap_file; do
            local filename=$(basename "$pcap_file")
            echo "--- $filename ---"
            
            # Informations de base
            local size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
            local date=$(stat -f%Sm "$pcap_file" 2>/dev/null || stat -c%y "$pcap_file" 2>/dev/null)
            
            echo "Taille: $((size / 1024)) KB"
            echo "Date: $date"
            
            # Test intégrité
            if timeout 10 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
                echo "Intégrité: OK"
                
                # Comptage rapide
                local total_packets=$(timeout 10 tshark -r "$pcap_file" -T fields -e frame.number 2>/dev/null | wc -l)
                local wifi_packets=$(timeout 10 tshark -r "$pcap_file" -Y "wlan" -T fields -e frame.number 2>/dev/null | wc -l)
                local eapol_packets=$(timeout 10 tshark -r "$pcap_file" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l)
                
                echo "Paquets total: $total_packets"
                echo "Paquets WiFi: $wifi_packets"
                echo "Paquets EAPOL: $eapol_packets"
                
                # Status pour handshake
                if [ "$eapol_packets" -gt 0 ]; then
                    echo "Status: POTENTIEL HANDSHAKE"
                elif [ "$wifi_packets" -gt 0 ]; then
                    echo "Status: TRAFIC WIFI"
                else
                    echo "Status: AUTRE PROTOCOLE"
                fi
            else
                echo "Intégrité: CORROMPU"
                echo "Status: INUTILISABLE"
            fi
            echo
        done
        
        echo "=== RECOMMANDATIONS ==="
        echo "1. Convertir les fichiers avec handshakes vers format 22000"
        echo "2. Supprimer les fichiers corrompus"
        echo "3. Archiver les fichiers sans handshakes"
        echo "4. Vérifier régulièrement l'intégrité des captures"
        echo
        echo "Rapport généré: $(date)"
        echo "=============================================================================="
        
    } > "$report_file"
    
    success "Rapport généré: $report_file"
    log "Contenu sauvegardé dans: $report_file"
}
