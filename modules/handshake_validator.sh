#!/bin/bash

# ==============================================================================
# Module de validation des handshakes WiFiCyberTools
# ==============================================================================

handshake_validator_menu() {
    header
    echo -e "${BLUE}✅ VALIDATION DES HANDSHAKES${NC}"
    
    local pcap_count=$(find "$CAPTURES_DIR" -name "*.pcap*" 2>/dev/null | wc -l)
    local converted_count=$(find "$CONVERTED_DIR" -name "*.hc22000" 2>/dev/null | wc -l)
    
    echo -e "  📁 Fichiers PCAP: ${GREEN}$pcap_count${NC}"
    echo -e "  🔄 Fichiers convertis: ${GREEN}$converted_count${NC}"
    
    echo
    echo "1) Validation complète des handshakes"
    echo "2) Conversion vers format 22000"
    echo "3) Analyse de la qualité des handshakes"
    echo "4) Nettoyage des fichiers invalides"
    echo "5) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-5]: " choice
    
    case $choice in
        1) validate_all_handshakes ;;
        2) convert_to_22000 ;;
        3) analyze_handshake_quality ;;
        4) cleanup_invalid_files ;;
        5) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    handshake_validator_menu
}

validate_all_handshakes() {
    header
    log "Validation complète des handshakes..."
    
    mkdir -p "$CONVERTED_DIR"
    
    local pcap_files=($(find "$CAPTURES_DIR" -name "*.pcap*" -type f))
    local total=${#pcap_files[@]}
    
    if [ "$total" -eq 0 ]; then
        warn "Aucun fichier PCAP trouvé"
        return 1
    fi
    
    log "Analyse de $total fichier(s)..."
    
    local valid_handshakes=0
    local pmkid_only=0
    local no_handshake=0
    local corrupted=0
    
    for pcap_file in "${pcap_files[@]}"; do
        local filename=$(basename "$pcap_file")
        local basename=$(basename "$pcap_file" .pcap)
        
        printf "\rValidation: %s" "$filename"
        
        # Test intégrité
        if ! timeout 10 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
            corrupted=$((corrupted + 1))
            echo "CORRUPTED" > "/tmp/handshake_${basename}.status"
            continue
        fi
        
        # Comptage EAPOL et PMKID
        local eapol_count=$(timeout 15 tshark -r "$pcap_file" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l)
        local pmkid_count=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.rsn.ie.pmkid" -T fields -e frame.number 2>/dev/null | wc -l)
        
        # Classification
        if [ "$eapol_count" -ge 4 ] && [ "$pmkid_count" -gt 0 ]; then
            valid_handshakes=$((valid_handshakes + 1))
            echo "FULL_HANDSHAKE_PMKID" > "/tmp/handshake_${basename}.status"
            echo "EAPOL: $eapol_count, PMKID: $pmkid_count" > "/tmp/handshake_${basename}.details"
        elif [ "$eapol_count" -ge 4 ]; then
            valid_handshakes=$((valid_handshakes + 1))
            echo "FULL_HANDSHAKE" > "/tmp/handshake_${basename}.status"
            echo "EAPOL: $eapol_count (4-way complete)" > "/tmp/handshake_${basename}.details"
        elif [ "$eapol_count" -ge 2 ]; then
            valid_handshakes=$((valid_handshakes + 1))
            echo "PARTIAL_HANDSHAKE" > "/tmp/handshake_${basename}.status"
            echo "EAPOL: $eapol_count (partial)" > "/tmp/handshake_${basename}.details"
        elif [ "$pmkid_count" -gt 0 ]; then
            pmkid_only=$((pmkid_only + 1))
            echo "PMKID_ONLY" > "/tmp/handshake_${basename}.status"
            echo "PMKID: $pmkid_count (no EAPOL)" > "/tmp/handshake_${basename}.details"
        else
            no_handshake=$((no_handshake + 1))
            echo "NO_HANDSHAKE" > "/tmp/handshake_${basename}.status"
            echo "No authentication data found" > "/tmp/handshake_${basename}.details"
        fi
    done
    
    echo
    echo
    success "Validation terminée:"
    echo "  🏆 Handshakes complets: $valid_handshakes"
    echo "  🔑 PMKID seulement: $pmkid_only"
    echo "  ❌ Sans handshake: $no_handshake"
    echo "  💥 Fichiers corrompus: $corrupted"
    echo "  📊 Total analysé: $total"
    
    # Affichage des meilleurs fichiers
    if [ "$valid_handshakes" -gt 0 ] || [ "$pmkid_only" -gt 0 ]; then
        echo
        echo -e "${GREEN}🎯 Fichiers recommandés pour conversion:${NC}"
        
        find "/tmp" -name "handshake_*.status" -exec grep -l "FULL_HANDSHAKE" {} \; | while read -r status_file; do
            local basename=$(basename "$status_file" .status | sed 's/handshake_//')
            local details=$(cat "/tmp/handshake_${basename}.details" 2>/dev/null || echo "Détails non disponibles")
            echo "  ⭐ ${basename}.pcap - $details"
        done
        
        find "/tmp" -name "handshake_*.status" -exec grep -l "PMKID_ONLY" {} \; | while read -r status_file; do
            local basename=$(basename "$status_file" .status | sed 's/handshake_//')
            local details=$(cat "/tmp/handshake_${basename}.details" 2>/dev/null || echo "Détails non disponibles")
            echo "  🔑 ${basename}.pcap - $details"
        done
    fi
}

convert_to_22000() {
    header
    log "Conversion vers format 22000 des fichiers PCAP dans $CAPTURES_DIR..."

    if ! command -v hcxpcapngtool >/dev/null 2>&1; then
        error "hcxpcapngtool non installé. Veuillez l'installer d'abord."
        return 1
    fi

    mkdir -p "$CONVERTED_DIR"

    shopt -s nullglob
    local files=("$CAPTURES_DIR"/*.pcap "$CAPTURES_DIR"/*.pcapng)

    if [ ${#files[@]} -eq 0 ]; then
        warn "Aucun fichier .pcap ou .pcapng trouvé dans $CAPTURES_DIR"
        return 0
    fi

    local converted=0
    local skipped=0
    local failed=0

    for FILE in "${files[@]}"; do
        local BASENAME=$(basename "$FILE")
        local OUTPUT="$CONVERTED_DIR/${BASENAME%.*}.hc22000"

        printf "[*] Traitement de %s ...\n" "$BASENAME"

        # Exécuter conversion, silencieux
        if hcxpcapngtool -o "$OUTPUT" "$FILE" > /dev/null 2>&1; then
            if [ -s "$OUTPUT" ]; then
                echo "    [+] Handshake trouvé → $OUTPUT"
                converted=$((converted + 1))
            else
                echo "    [-] Aucun handshake valide trouvé"
                rm -f "$OUTPUT"
                failed=$((failed + 1))
            fi
        else
            echo "    [-] Erreur durant la conversion"
            rm -f "$OUTPUT"
            failed=$((failed + 1))
        fi
    done

    echo
    echo "Conversion terminée:"
    echo "  ✅ Convertis avec succès : $converted"
    echo "  ❌ Échecs ou aucun handshake : $failed"
}

# --- MODULE 3: Analyse de la qualité des handshakes ---

analyze_handshake_quality() {
    header
    log "Analyse de la qualité des handshakes dans $CAPTURES_DIR..."

    local pcap_files=($(find "$CAPTURES_DIR" -name "*.pcap*" -type f))
    if [ ${#pcap_files[@]} -eq 0 ]; then
        warn "Aucun fichier PCAP trouvé à analyser"
        return 1
    fi
    
    echo -e "${CYAN}Analyse détaillée de la qualité des handshakes :${NC}"
    echo

    for pcap_file in "${pcap_files[@]}"; do
        local filename=$(basename "$pcap_file")
        echo "🔍 Analyse : $filename"
        
        # Vérifier intégrité sommaire
        if ! timeout 10 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
            echo "  ⚠️  Fichier corrompu ou illisible"
            echo
            continue
        fi
        
        # Nombre de paquets EAPOL
        local eapol_count=$(timeout 15 tshark -r "$pcap_file" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l)
        # Nombre de paquets PMKID
        local pmkid_count=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.rsn.ie.pmkid" -T fields -e frame.number 2>/dev/null | wc -l)
        # Nombre total paquets
        local total_packets=$(timeout 15 tshark -r "$pcap_file" -T fields -e frame.number 2>/dev/null | wc -l)
        
        echo "  📊 Paquets total : $total_packets"
        echo "  🤝 Paquets EAPOL : $eapol_count"
        echo "  🔐 Paquets PMKID : $pmkid_count"
        
        # Évaluation qualité handshake
        if [ "$eapol_count" -ge 4 ]; then
            echo -e "  🏆 Qualité : \033[32mEXCELLENTE\033[0m (4-way handshake complet)"
        elif [ "$eapol_count" -ge 2 ]; then
            echo -e "  👍 Qualité : \033[33mPARTIELLE\033[0m (handshake partiel)"
        elif [ "$pmkid_count" -gt 0 ]; then
            echo -e "  👍 Qualité : \033[33mPMKID seulement\033[0m"
        elif [ "$total_packets" -gt 100 ]; then
            echo -e "  ⚠️ Qualité : \033[33mPeu probable handshake\033[0m (trafic wifi faible)"
        else
            echo -e "  ❌ Qualité : \033[31mInsuffisante ou absence de handshake\033[0m"
        fi
        
        echo
    done
}

# --- MODULE 4: Nettoyage des fichiers invalides ---

cleanup_invalid_files() {
    header
    echo -e "${RED}🧹 NETTOYAGE DES FICHIERS INVALIDES${NC}"
    echo "Cette opération supprime définitivement:"
    echo " - les fichiers corrompus"
    echo " - les fichiers sans handshakes valides (pas d’EAPOL ou PMKID)"
    echo " - les fichiers très petits (moins de 1KB)"
    echo
    
    read -p "Confirmer la suppression? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log "Nettoyage annulé"
        return 0
    fi
    
    local deleted=0
    local freed_space=0
    
    for pcap_file in "$CAPTURES_DIR"/*.pcap "$CAPTURES_DIR"/*.pcapng; do
        [ -e "$pcap_file" ] || continue
        local filename=$(basename "$pcap_file")
        local file_size=$(stat -c%s "$pcap_file" 2>/dev/null || echo 0)
        
        # Fichier très petit
        if [ "$file_size" -lt 1024 ]; then
            log "Suppression (trop petit): $filename"
            rm -f "$pcap_file"
            deleted=$((deleted + 1))
            freed_space=$((freed_space + file_size))
            continue
        fi
        
        # Test intégrité avec tshark
        if ! timeout 10 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
            log "Suppression (corrompu): $filename"
            rm -f "$pcap_file"
            deleted=$((deleted + 1))
            freed_space=$((freed_space + file_size))
            continue
        fi
        
        # Vérifier présence de handshake (EAPOL ou PMKID)
        local eapol_count=$(timeout 15 tshark -r "$pcap_file" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l)
        local pmkid_count=$(timeout 15 tshark -r "$pcap_file" -Y "wlan.rsn.ie.pmkid" -T fields -e frame.number 2>/dev/null | wc -l)
        
        if [ "$eapol_count" -eq 0 ] && [ "$pmkid_count" -eq 0 ]; then
            log "Suppression (pas de handshake): $filename"
            rm -f "$pcap_file"
            deleted=$((deleted + 1))
            freed_space=$((freed_space + file_size))
        fi
    done
    
    success "Nettoyage terminé:"
    echo "  🗑️  Fichiers supprimés : $deleted"
    echo "  💾 Espace libéré : $((freed_space / 1024)) KB"
}