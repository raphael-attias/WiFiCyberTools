#!/bin/bash

# ==============================================================================
# Module de nettoyage PCAP WiFiCyberTools
# ==============================================================================

pcap_cleaner_menu() {
    header
    echo -e "${BLUE}🧹 NETTOYAGE DES CAPTURES${NC}"
    
    local pcap_count=$(find "$CAPTURES_DIR" -name "*.pcap*" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$CAPTURES_DIR" 2>/dev/null | cut -f1)
    
    echo -e "  📁 Fichiers PCAP: ${GREEN}$pcap_count${NC}"
    echo -e "  💾 Taille totale: ${GREEN}$total_size${NC}"
    
    echo
    echo "1) Nettoyage automatique intelligent"
    echo "2) Suppression des doublons"
    echo "3) Suppression des fichiers corrompus"
    echo "4) Suppression des captures vides"
    echo "5) Archivage des anciens fichiers"
    echo "6) Nettoyage par critères personnalisés"
    echo "7) Statistiques d'occupation disque"
    echo "8) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-8]: " choice
    
    case $choice in
        1) intelligent_cleanup ;;
        2) remove_duplicates ;;
        3) remove_corrupted ;;
        4) remove_empty ;;
        5) archive_old_files ;;
        6) custom_cleanup ;;
        7) disk_usage_stats ;;
        8) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    pcap_cleaner_menu
}

intelligent_cleanup() {
    header
    log "Nettoyage automatique intelligent..."
    
    echo -e "${CYAN}Analyse préliminaire...${NC}"
    
    # Statistiques avant nettoyage
    local initial_count=$(find "$CAPTURES_DIR" -name "*.pcap*" | wc -l)
    local initial_size=$(du -sb "$CAPTURES_DIR" 2>/dev/null | cut -f1)
    
    echo "  📊 Fichiers actuels: $initial_count"
    echo "  💾 Taille actuelle: $((initial_size / 1024 / 1024)) MB"
    echo
    
    # Analyse de la qualité
    log "Classification des fichiers par qualité..."
    
    local excellent=0
    local good=0
    local poor=0
    local useless=0
    local corrupted=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
        
        printf "\rAnalyse: %s" "$filename"
        
        # Test de corruption
        if ! timeout 5 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
            echo "CORRUPTED" > "/tmp/cleanup_${filename}.status"
            continue
        fi
        
        # Analyse du contenu
        local eapol_count=$(timeout 10 tshark -r "$pcap_file" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l)
        local pmkid_count=$(timeout 10 tshark -r "$pcap_file" -Y "wlan.rsn.ie.pmkid" -T fields -e frame.number 2>/dev/null | wc -l)
        local wifi_count=$(timeout 10 tshark -r "$pcap_file" -Y "wlan" -T fields -e frame.number 2>/dev/null | wc -l)
        
        # Classification
        if [ "$eapol_count" -ge 4 ] && [ "$pmkid_count" -gt 0 ]; then
            echo "EXCELLENT" > "/tmp/cleanup_${filename}.status"
        elif [ "$eapol_count" -ge 2 ] || [ "$pmkid_count" -gt 0 ]; then
            echo "GOOD" > "/tmp/cleanup_${filename}.status"
        elif [ "$wifi_count" -ge 50 ]; then
            echo "POOR" > "/tmp/cleanup_${filename}.status"
        elif [ "$file_size" -lt 5120 ] || [ "$wifi_count" -lt 10 ]; then
            echo "USELESS" > "/tmp/cleanup_${filename}.status"
        else
            echo "POOR" > "/tmp/cleanup_${filename}.status"
        fi
    done
    
    echo
    echo
    
    # Comptage par catégorie
    excellent=$(find "/tmp" -name "cleanup_*.status" -exec grep -l "EXCELLENT" {} \; 2>/dev/null | wc -l)
    good=$(find "/tmp" -name "cleanup_*.status" -exec grep -l "GOOD" {} \; 2>/dev/null | wc -l)
    poor=$(find "/tmp" -name "cleanup_*.status" -exec grep -l "POOR" {} \; 2>/dev/null | wc -l)
    useless=$(find "/tmp" -name "cleanup_*.status" -exec grep -l "USELESS" {} \; 2>/dev/null | wc -l)
    corrupted=$(find "/tmp" -name "cleanup_*.status" -exec grep -l "CORRUPTED" {} \; 2>/dev/null | wc -l)
    
    echo -e "${CYAN}Classification terminée:${NC}"
    echo "  🏆 Excellents (handshake complet + PMKID): $excellent"
    echo "  ✅ Bons (handshake ou PMKID): $good"
    echo "  ⚠️  Faibles (peu de données): $poor"
    echo "  🗑️  Inutiles (très peu de données): $useless"
    echo "  💥 Corrompus: $corrupted"
    echo
    
    # Proposer le nettoyage
    echo -e "${YELLOW}Actions recommandées:${NC}"
    if [ "$useless" -gt 0 ]; then
        echo "  • Supprimer $useless fichier(s) inutile(s)"
    fi
    if [ "$corrupted" -gt 0 ]; then
        echo "  • Supprimer $corrupted fichier(s) corrompu(s)"
    fi
    if [ "$poor" -gt 10 ]; then
        echo "  • Archiver $poor fichier(s) de qualité faible"
    fi
    
    echo
    read -p "Appliquer le nettoyage recommandé? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        apply_intelligent_cleanup
    else
        log "Nettoyage annulé"
    fi
    
    # Nettoyage des fichiers temporaires
    rm -f /tmp/cleanup_*.status
}

apply_intelligent_cleanup() {
    local deleted=0
    local archived=0
    local freed_space=0
    
    # Créer le répertoire d'archive si nécessaire
    mkdir -p "$DATA_DIR/archive"
    
    # Supprimer les fichiers corrompus
    find "/tmp" -name "cleanup_*.status" -exec grep -l "CORRUPTED" {} \; | while read -r status_file; do
        local filename=$(basename "$status_file" .status | sed 's/cleanup_//')
        local pcap_file=$(find "$CAPTURES_DIR" -name "$filename" -type f)
        
        if [ -f "$pcap_file" ]; then
            local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
            log "Suppression (corrompu): $filename"
            rm -f "$pcap_file"
            deleted=$((deleted + 1))
            freed_space=$((freed_space + file_size))
        fi
    done
    
    # Supprimer les fichiers inutiles
    find "/tmp" -name "cleanup_*.status" -exec grep -l "USELESS" {} \; | while read -r status_file; do
        local filename=$(basename "$status_file" .status | sed 's/cleanup_//')
        local pcap_file=$(find "$CAPTURES_DIR" -name "$filename" -type f)
        
        if [ -f "$pcap_file" ]; then
            local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
            log "Suppression (inutile): $filename"
            rm -f "$pcap_file"
            deleted=$((deleted + 1))
            freed_space=$((freed_space + file_size))
        fi
    done
    
    # Archiver les fichiers de qualité faible (optionnel)
    if [ "$poor" -gt 20 ]; then
        echo
        read -p "Archiver également les fichiers de qualité faible? [y/N]: " archive_poor
        
        if [[ "$archive_poor" =~ ^[Yy] ]]; then
            find "/tmp" -name "cleanup_*.status" -exec grep -l "POOR" {} \; | while read -r status_file; do
                local filename=$(basename "$status_file" .status | sed 's/cleanup_//')
                local pcap_file=$(find "$CAPTURES_DIR" -name "$filename" -type f)
                
                if [ -f "$pcap_file" ]; then
                    log "Archivage: $filename"
                    mv "$pcap_file" "$DATA_DIR/archive/"
                    archived=$((archived + 1))
                fi
            done
        fi
    fi
    
    success "Nettoyage intelligent terminé:"
    echo "  🗑️  Fichiers supprimés: $deleted"
    echo "  📦 Fichiers archivés: $archived"
    echo "  💾 Espace libéré: $((freed_space / 1024 / 1024)) MB"
}

remove_duplicates() {
    header
    log "Suppression des doublons..."
    
    # Recherche par taille et somme MD5
    local temp_file="/tmp/pcap_checksums.txt"
    
    log "Calcul des empreintes MD5..."
    find "$CAPTURES_DIR" -name "*.pcap*" -type f -exec md5sum {} \; > "$temp_file"
    
    # Identifier les doublons
    local duplicates=$(awk '{print $1}' "$temp_file" | sort | uniq -d)
    
    if [ -z "$duplicates" ]; then
        success "Aucun doublon trouvé"
        return 0
    fi
    
    local duplicate_count=0
    local freed_space=0
    
    echo "$duplicates" | while read -r md5_hash; do
        # Trouver tous les fichiers avec ce hash
        local files_with_hash=($(grep "^$md5_hash" "$temp_file" | cut -d' ' -f2-))
        local file_count=${#files_with_hash[@]}
        
        if [ "$file_count" -gt 1 ]; then
            echo "Doublons trouvés (MD5: ${md5_hash:0:8}...):"
            
            # Garder le plus ancien, supprimer les autres
            local oldest_file="${files_with_hash[0]}"
            local oldest_date=$(stat -f%Sm -t%s "$oldest_file" 2>/dev/null || stat -c%Y "$oldest_file" 2>/dev/null)
            
            for file in "${files_with_hash[@]}"; do
                local file_date=$(stat -f%Sm -t%s "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null)
                if [ "$file_date" -lt "$oldest_date" ]; then
                    oldest_file="$file"
                    oldest_date="$file_date"
                fi
            done
            
            echo "  📁 Conservé: $(basename "$oldest_file")"
            
            for file in "${files_with_hash[@]}"; do
                if [ "$file" != "$oldest_file" ]; then
                    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                    echo "  🗑️  Supprimé: $(basename "$file")"
                    rm -f "$file"
                    duplicate_count=$((duplicate_count + 1))
                    freed_space=$((freed_space + file_size))
                fi
            done
            echo
        fi
    done
    
    success "Suppression des doublons terminée:"
    echo "  🗑️  Doublons supprimés: $duplicate_count"
    echo "  💾 Espace libéré: $((freed_space / 1024 / 1024)) MB"
    
    rm -f "$temp_file"
}

remove_corrupted() {
    header
    log "Suppression des fichiers corrompus..."
    
    local corrupted=0
    local freed_space=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        
        printf "\rVérification: %s" "$filename"
        
        # Test avec file
        if ! file "$pcap_file" | grep -q "pcap"; then
            local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
            warn "Fichier suspect (format): $filename"
            rm -f "$pcap_file"
            corrupted=$((corrupted + 1))
            freed_space=$((freed_space + file_size))
            continue
        fi
        
        # Test avec tshark
        if ! timeout 5 tshark -r "$pcap_file" -c 1 >/dev/null 2>&1; then
            local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
            warn "Fichier corrompu (lecture): $filename"
            rm -f "$pcap_file"
            corrupted=$((corrupted + 1))
            freed_space=$((freed_space + file_size))
        fi
    done
    
    echo
    success "Nettoyage des fichiers corrompus terminé:"
    echo "  🗑️  Fichiers corrompus supprimés: $corrupted"
    echo "  💾 Espace libéré: $((freed_space / 1024)) KB"
}

remove_empty() {
    header
    log "Suppression des captures vides..."
    
    local empty=0
    local freed_space=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
        
        printf "\rAnalyse: %s" "$filename"
        
        # Fichiers très petits
        if [ "$file_size" -lt 1024 ]; then
            log "Suppression (taille < 1KB): $filename"
            rm -f "$pcap_file"
            empty=$((empty + 1))
            freed_space=$((freed_space + file_size))
            continue
        fi
        
        # Test contenu WiFi
        local wifi_count=$(timeout 10 tshark -r "$pcap_file" -Y "wlan" -T fields -e frame.number 2>/dev/null | wc -l)
        
        if [ "$wifi_count" -eq 0 ]; then
            log "Suppression (pas de trafic WiFi): $filename"
            rm -f "$pcap_file"
            empty=$((empty + 1))
            freed_space=$((freed_space + file_size))
        elif [ "$wifi_count" -lt 5 ]; then
            log "Suppression (trafic WiFi insuffisant: $wifi_count): $filename"
            rm -f "$pcap_file"
            empty=$((empty + 1))
            freed_space=$((freed_space + file_size))
        fi
    done
    
    echo
    success "Suppression des captures vides terminée:"
    echo "  🗑️  Captures vides supprimées: $empty"
    echo "  💾 Espace libéré: $((freed_space / 1024)) KB"
}

archive_old_files() {
    header
    log "Archivage des anciens fichiers..."
    
    read -p "Archiver les fichiers de plus de combien de jours? [30]: " days
    days=${days:-30}
    
    mkdir -p "$DATA_DIR/archive"
    
    local archived=0
    local archive_size=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f -mtime "+$days" | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        local file_size=$(stat -f%z "$pcap_file" 2>/dev/null || stat -c%s "$pcap_file" 2>/dev/null)
        
        log "Archivage: $filename"
        mv "$pcap_file" "$DATA_DIR/archive/"
        archived=$((archived + 1))
        archive_size=$((archive_size + file_size))
    done
    
    success "Archivage terminé:"
    echo "  📦 Fichiers archivés: $archived"
    echo "  💾 Taille archivée: $((archive_size / 1024 / 1024)) MB"
    echo "  📁 Répertoire archive: $DATA_DIR/archive"
}

custom_cleanup() {
    header
    echo -e "${BLUE}🔧 NETTOYAGE PERSONNALISÉ${NC}"
    echo
    echo "Critères de nettoyage:"
    echo "1) Par âge (plus de X jours)"
    echo "2) Par taille (moins de X KB)"
    echo "3) Par contenu (moins de X paquets WiFi)"
    echo "4) Par absence de handshakes"
    echo "5) Combinaison de critères"
    echo
    
    read -p "Votre choix [1-5]: " criteria
    
    case $criteria in
        1) cleanup_by_age ;;
        2) cleanup_by_size ;;
        3) cleanup_by_content ;;
        4) cleanup_no_handshakes ;;
        5) cleanup_combined ;;
        *) warn "Critère invalide" ;;
    esac
}

cleanup_by_age() {
    read -p "Supprimer les fichiers de plus de combien de jours? [7]: " days
    days=${days:-7}
    
    local deleted=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f -mtime "+$days" | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        log "Suppression (âge > $days jours): $filename"
        rm -f "$pcap_file"
        deleted=$((deleted + 1))
    done
    
    success "$deleted fichier(s) supprimé(s) par critère d'âge"
}

cleanup_by_size() {
    read -p "Supprimer les fichiers de moins de combien de KB? [5]: " min_size
    min_size=${min_size:-5}
    
    local deleted=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f -size "-${min_size}k" | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        log "Suppression (taille < ${min_size}KB): $filename"
        rm -f "$pcap_file"
        deleted=$((deleted + 1))
    done
    
    success "$deleted fichier(s) supprimé(s) par critère de taille"
}

cleanup_no_handshakes() {
    log "Suppression des fichiers sans handshakes..."
    
    local deleted=0
    
    find "$CAPTURES_DIR" -name "*.pcap*" -type f | while IFS= read -r pcap_file; do
        local filename=$(basename "$pcap_file")
        
        # Test présence EAPOL ou
