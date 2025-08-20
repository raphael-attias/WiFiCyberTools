#!/bin/bash

# ==============================================================================
# Module de synchronisation Pwnagotchi WiFiCyberTools
# ==============================================================================

pwnagotchi_sync_menu() {
    header
    echo -e "${BLUE}📥 SYNCHRONISATION PWNAGOTCHI${NC}"
    
    # Status rapide
    local remote_count=0
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=3 -o BatchMode=yes \
       "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" exit 2>/dev/null; then
        remote_count=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
            "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' 2>/dev/null | wc -l" 2>/dev/null || echo "0")
        echo -e "  📡 Fichiers disponibles sur Pwnagotchi: ${GREEN}$remote_count${NC}"
    else
        echo -e "  📡 Pwnagotchi: ${RED}Non accessible${NC}"
    fi
    
    local local_count=$(find "$CAPTURES_DIR" -name "*.pcap*" 2>/dev/null | wc -l)
    echo -e "  💾 Fichiers locaux: ${GREEN}$local_count${NC}"
    
    echo
    echo "1) Synchronisation complète (tous les fichiers)"
    echo "2) Synchronisation incrémentale (nouveaux uniquement)"
    echo "3) Synchronisation sélective (par date/taille)"
    echo "4) Prévisualisation des fichiers à synchroniser"
    echo "5) Nettoyage des fichiers synchronisés sur Pwnagotchi"
    echo "6) Configuration de la synchronisation automatique"
    echo "7) Statistiques de synchronisation"
    echo "8) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-8]: " choice
    
    case $choice in
        1) sync_all ;;
        2) sync_incremental ;;
        3) sync_selective ;;
        4) preview_sync ;;
        5) cleanup_remote ;;
        6) setup_auto_sync ;;
        7) sync_statistics ;;
        8) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    pwnagotchi_sync_menu
}

sync_all() {
    header
    log "Synchronisation complète depuis $PWNAGOTCHI_IP..."
    
    # Vérifier la connexion SSH
    if [ ! -f "$SSH_KEY_PATH" ]; then
        error "Clé SSH non configurée. Configurez d'abord la clé SSH."
        return 1
    fi
    
    # Test de connectivité
    if ! ping -c 1 -W 3 "$PWNAGOTCHI_IP" >/dev/null 2>&1; then
        error "Pwnagotchi non accessible à $PWNAGOTCHI_IP"
        return 1
    fi
    
    # Créer le répertoire local
    mkdir -p "$CAPTURES_DIR"
    
    # Vérifier l'espace disque
    local available_space=$(df "$CAPTURES_DIR" | tail -1 | awk '{print $4}')
    local remote_size=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "du -s $PWNAGOTCHI_HANDSHAKE_DIR 2>/dev/null | cut -f1" || echo "0")
    
    if [ "$remote_size" -gt "$available_space" ]; then
        warn "Espace disque insuffisant. Requis: $((remote_size / 1024))MB, Disponible: $((available_space / 1024))MB"
        read -p "Continuer quand même? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
            return 1
        fi
    fi
    
    # Synchronisation avec rsync
    log "Démarrage de la synchronisation rsync..."
    local start_time=$(date +%s)
    
    if rsync -avz --progress --stats \
       --timeout=300 \
       --exclude="*.tmp" \
       --exclude="*.log" \
       -e "ssh -i $SSH_KEY_PATH -o ConnectTimeout=10" \
       "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP:$PWNAGOTCHI_HANDSHAKE_DIR/" \
       "$CAPTURES_DIR/"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        success "Synchronisation terminée en ${duration}s"
        
        # Statistiques finales
        local synced_count=$(find "$CAPTURES_DIR" -name "*.pcap*" | wc -l)
        local total_size=$(du -sh "$CAPTURES_DIR" 2>/dev/null | cut -f1)
        
        echo -e "${CYAN}📊 Statistiques:${NC}"
        echo "  📁 Fichiers synchronisés: $synced_count"
        echo "  💾 Taille totale: $total_size"
        echo "  ⏱️  Durée: ${duration}s"
        echo "  🚀 Débit moyen: $((remote_size / duration / 1024))KB/s" 2>/dev/null || echo "  🚀 Débit: Non calculable"
        
        # Mettre à jour le cache de synchronisation
        update_sync_cache
        
    else
        error "Échec de la synchronisation"
        return 1
    fi
}

sync_incremental() {
    header
    log "Synchronisation incrémentale..."
    
    # Créer un fichier de cache pour les fichiers déjà synchronisés
    local cache_file="$LOG_DIR/sync_cache.txt"
    touch "$cache_file"
    
    # Lister les fichiers distants avec leurs dates
    local remote_list="/tmp/remote_files_with_dates.txt"
    ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' -type f -exec stat -c'%Y:%n' {} \;" > "$remote_list" 2>/dev/null
    
    if [ ! -s "$remote_list" ]; then
        warn "Impossible de lister les fichiers distants"
        return 1
    fi
    
    # Identifier les nouveaux fichiers et fichiers modifiés
    local new_files="/tmp/new_files.txt"
    > "$new_files"
    
    while IFS=: read -r remote_timestamp remote_file; do
        local filename=$(basename "$remote_file")
        local local_file="$CAPTURES_DIR/$filename"
        
        # Vérifier si le fichier existe localement et comparer les timestamps
        if [ -f "$local_file" ]; then
            local local_timestamp=$(stat -c%Y "$local_file" 2>/dev/null || echo "0")
            
            if [ "$remote_timestamp" -gt "$local_timestamp" ]; then
                echo "$remote_file" >> "$new_files"
            fi
        else
            echo "$remote_file" >> "$new_files"
        fi
    done < "$remote_list"
    
    local new_count=$(wc -l < "$new_files" 2>/dev/null || echo "0")
    
    if [ "$new_count" -eq 0 ]; then
        success "Aucun nouveau fichier à synchroniser"
        return 0
    fi
    
    log "$new_count nouveau(x)/modifié(s) fichier(s) détecté(s)"
    
    # Afficher un échantillon des nouveaux fichiers
    echo -e "${CYAN}Aperçu des nouveaux fichiers:${NC}"
    head -5 "$new_files" | while read -r file; do
        echo "  📁 $(basename "$file")"
    done
    
    if [ "$new_count" -gt 5 ]; then
        echo "  ... et $((new_count - 5)) autre(s)"
    fi
    
    echo
    read -p "Synchroniser ces fichiers? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        log "Synchronisation annulée"
        return 0
    fi
    
    # Synchroniser les nouveaux fichiers
    local synced=0
    local failed=0
    local current=0
    
    while IFS= read -r remote_file; do
        current=$((current + 1))
        local filename=$(basename "$remote_file")
        
        printf "\r[%d/%d] Téléchargement: %s" "$current" "$new_count" "$filename"
        
        if scp -i "$SSH_KEY_PATH" \
            "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP:$remote_file" \
            "$CAPTURES_DIR/" 2>/dev/null; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
    done < "$new_files"
    
    echo
    success "Synchronisation incrémentale terminée:"
    echo "  ✅ Synchronisés: $synced"
    echo "  ❌ Échecs: $failed"
    
    # Mettre à jour le cache
    update_sync_cache
    
    rm -f "$remote_list" "$new_files"
}

sync_selective() {
    header
    echo -e "${BLUE}📋 SYNCHRONISATION SÉLECTIVE${NC}"
    echo
    echo "Critères de sélection:"
    echo "1) Par date (derniers X jours)"
    echo "2) Par taille (fichiers > X KB)"
    echo "3) Par pattern ESSID (contient un mot)"
    echo "4) Par période (entre deux dates)"
    echo "5) Manuel (sélection fichier par fichier)"
    echo
    
    read -p "Votre choix [1-5]: " criteria
    
    case $criteria in
        1) sync_by_date ;;
        2) sync_by_size ;;
        3) sync_by_pattern ;;
        4) sync_by_period ;;
        5) sync_manual_selection ;;
        *) warn "Critère invalide" ;;
    esac
}

sync_by_date() {
    read -p "Nombre de jours [7]: " days
    days=${days:-7}
    
    log "Synchronisation des fichiers des derniers $days jours..."
    
    # Utiliser find avec critère de date sur le Pwnagotchi
    local files_to_sync="/tmp/files_by_date.txt"
    ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' -type f -mtime -$days" \
        > "$files_to_sync"
    
    local count=$(wc -l < "$files_to_sync")
    log "$count fichier(s) des derniers $days jours trouvé(s)"
    
    if [ "$count" -gt 0 ]; then
        sync_file_list "$files_to_sync"
    else
        warn "Aucun fichier récent trouvé"
    fi
    
    rm -f "$files_to_sync"
}

sync_by_size() {
    read -p "Taille minimum en KB [100]: " min_size
    min_size=${min_size:-100}
    
    log "Synchronisation des fichiers > ${min_size}KB..."
    
    # Lister avec tailles et filtrer
    local files_to_sync="/tmp/files_by_size.txt"
    ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' -type f -size +${min_size}k" \
        > "$files_to_sync"
    
    local count=$(wc -l < "$files_to_sync")
    log "$count fichier(s) > ${min_size}KB trouvé(s)"
    
    if [ "$count" -gt 0 ]; then
        sync_file_list "$files_to_sync"
    else
        warn "Aucun fichier de taille suffisante trouvé"
    fi
    
    rm -f "$files_to_sync"
}

sync_by_pattern() {
    read -p "Pattern ESSID (ex: Freebox, Livebox): " pattern
    
    if [ -z "$pattern" ]; then
        warn "Pattern vide"
        return 1
    fi
    
    log "Synchronisation des fichiers contenant '$pattern'..."
    
    # Rechercher les fichiers dont le nom contient le pattern
    local files_to_sync="/tmp/files_by_pattern.txt"
    ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*${pattern}*' -type f" \
        > "$files_to_sync"
    
    local count=$(wc -l < "$files_to_sync")
    log "$count fichier(s) contenant '$pattern' trouvé(s)"
    
    if [ "$count" -gt 0 ]; then
        # Afficher les fichiers trouvés
        echo -e "${CYAN}Fichiers correspondants:${NC}"
        head -10 "$files_to_sync" | while read -r file; do
            echo "  📁 $(basename "$file")"
        done
        
        if [ "$count" -gt 10 ]; then
            echo "  ... et $((count - 10)) autre(s)"
        fi
        
        echo
        read -p "Synchroniser ces fichiers? [Y/n]: " confirm
        if [[ ! "$confirm" =~ ^[Nn] ]]; then
            sync_file_list "$files_to_sync"
        fi
    else
        warn "Aucun fichier correspondant au pattern '$pattern'"
    fi
    
    rm -f "$files_to_sync"
}

sync_file_list() {
    local file_list="$1"
    local count=$(wc -l < "$file_list")
    
    if [ "$count" -eq 0 ]; then
        warn "Aucun fichier correspondant aux critères"
        return
    fi
    
    log "Synchronisation de $count fichier(s)..."
    
    local current=0
    local synced=0
    local failed=0
    
    while IFS= read -r remote_file; do
        current=$((current + 1))
        local filename=$(basename "$remote_file")
        
        printf "\r[%d/%d] %s" "$current" "$count" "$filename"
        
        if scp -i "$SSH_KEY_PATH" \
            "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP:$remote_file" \
            "$CAPTURES_DIR/" 2>/dev/null; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
    done < "$file_list"
    
    echo
    success "Synchronisation terminée:"
    echo "  ✅ Synchronisés: $synced"
    echo "  ❌ Échecs: $failed"
}

preview_sync() {
    header
    log "Prévisualisation des fichiers à synchroniser..."
    
    # Lister les fichiers distants avec détails
    local remote_preview="/tmp/remote_preview.txt"
    ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' -type f -exec ls -lah {} \;" \
        > "$remote_preview" 2>/dev/null
    
    if [ ! -s "$remote_preview" ]; then
        warn "Impossible de lister les fichiers distants"
        return 1
    fi
    
    local total_files=$(wc -l < "$remote_preview")
    local total_size=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "du -sh $PWNAGOTCHI_HANDSHAKE_DIR 2>/dev/null | cut -f1" || echo "Inconnu")
    
    echo -e "${CYAN}Fichiers disponibles sur le Pwnagotchi:${NC}"
    echo "  📊 Total: $total_files fichiers"
    echo "  💾 Taille: $total_size"
    echo
    
    # Afficher les fichiers avec pagination
    local display_count=20
    echo -e "${CYAN}Aperçu des fichiers (${display_count} premiers):${NC}"
    
    head -"$display_count" "$remote_preview" | while IFS= read -r line; do
        local filename=$(echo "$line" | awk '{print $NF}')
        local size=$(echo "$line" | awk '{print $5}')
        local date=$(echo "$line" | awk '{print $6, $7, $8}')
        
        # Vérifier si déjà local
        local status="🆕"
        local local_file="$CAPTURES_DIR/$(basename "$filename")"
        if [ -f "$local_file" ]; then
            # Comparer les tailles
            local local_size=$(stat -c%s "$local_file" 2>/dev/null || echo "0")
            local remote_size_bytes=$(echo "$line" | awk '{print $5}')
            
            if [ "$local_size" -eq "$remote_size_bytes" ]; then
                status="✅"
            else
                status="🔄"
            fi
        fi
        
        echo "  $status $(basename "$filename") - $size - $date"
    done
    
    if [ "$total_files" -gt "$display_count" ]; then
        echo "  ... et $((total_files - display_count)) fichier(s) supplémentaire(s)"
    fi
    
    echo
    echo "Légende: 🆕 Nouveau  ✅ Identique  🔄 Modifié"
    
    rm -f "$remote_preview"
}

cleanup_remote() {
    header
    echo -e "${RED}🧹 NETTOYAGE DU PWNAGOTCHI${NC}"
    echo
    echo "⚠️  ATTENTION: Cette opération supprime des fichiers sur le Pwnagotchi!"
    echo
    echo "Options de nettoyage:"
    echo "1) Supprimer les fichiers déjà synchronisés localement"
    echo "2) Supprimer les fichiers de plus de X jours"
    echo "3) Supprimer les fichiers de moins de X KB"
    echo "4) Annuler"
    echo
    
    read -p "Votre choix [1-4]: " cleanup_choice
    
    case $cleanup_choice in
        1) cleanup_synced_files ;;
        2) cleanup_old_files_remote ;;
        3) cleanup_small_files_remote ;;
        4) log "Nettoyage annulé" ;;
        *) warn "Option invalide" ;;
    esac
}

cleanup_synced_files() {
    log "Identification des fichiers déjà synchronisés..."
    
    local to_delete="/tmp/files_to_delete.txt"
    > "$to_delete"
    
    # Comparer les fichiers locaux avec les fichiers distants
    ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
        "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' -type f -exec basename {} \;" | \
    while read -r remote_filename; do
        local local_file="$CAPTURES_DIR/$remote_filename"
        
        if [ -f "$local_file" ]; then
            # Vérifier que les tailles correspondent
            local local_size=$(stat -c%s "$local_file" 2>/dev/null)
            local remote_size=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
                "stat -c%s $PWNAGOTCHI_HANDSHAKE_DIR/$remote_filename 2>/dev/null" || echo "0")
            
            if [ "$local_size" -eq "$remote_size" ]; then
                echo "$PWNAGOTCHI_HANDSHAKE_DIR/$remote_filename" >> "$to_delete"
            fi
        fi
    done
    
    local delete_count=$(wc -l < "$to_delete" 2>/dev/null || echo "0")
    
    if [ "$delete_count" -eq 0 ]; then
        success "Aucun fichier à supprimer"
        return 0
    fi
    
    log "$delete_count fichier(s) identique(s) trouvé(s)"
    
    echo -e "${YELLOW}Fichiers à supprimer:${NC}"
    head -10 "$to_delete" | while read -r file; do
        echo "  🗑️  $(basename "$file")"
    done
    
    if [ "$delete_count" -gt 10 ]; then
        echo "  ... et $((delete_count - 10)) autre(s)"
    fi
    
    echo
    echo -e "${RED}⚠️  Cette action est IRRÉVERSIBLE!${NC}"
    read -p "Confirmer la suppression sur le Pwnagotchi? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        log "Suppression des fichiers sur le Pwnagotchi..."
        
        local deleted=0
        while IFS= read -r file_to_delete; do
            if ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
               "rm -f '$file_to_delete'" 2>/dev/null; then
                deleted=$((deleted + 1))
                printf "\r[%d/%d] Supprimé: %s" "$deleted" "$delete_count" "$(basename "$file_to_delete")"
            fi
        done < "$to_delete"
        
        echo
        success "$deleted fichier(s) supprimé(s) du Pwnagotchi"
        
        # Calculer l'espace libéré
        local freed_space=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
            "df -h $PWNAGOTCHI_HANDSHAKE_DIR | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "Inconnu")
        log "Espace disponible sur Pwnagotchi: $freed_space"
    else
        log "Suppression annulée"
    fi
    
    rm -f "$to_delete"
}

setup_auto_sync() {
    header
    echo -e "${BLUE}⚙️ SYNCHRONISATION AUTOMATIQUE${NC}"
    echo
    echo "Configuration d'une synchronisation automatique via cron"
    echo
    
    read -p "Intervalle de synchronisation en heures [24]: " interval
    interval=${interval:-24}
    
    read -p "Type de synchronisation (all/incremental) [incremental]: " sync_type
    sync_type=${sync_type:-incremental}
    
    # Créer le script de synchronisation automatique
    local auto_sync_script="/usr/local/bin/wificybertools-autosync"
    
    cat > "$auto_sync_script" << EOF
#!/bin/bash
# Synchronisation automatique WiFiCyberTools
export SCRIPT_DIR="$SCRIPT_DIR"
source "$CONFIG_FILE"
cd "$SCRIPT_DIR"

# Log de début
echo "\$(date): Début synchronisation automatique" >> "$LOG_DIR/autosync.log"

# Chargement du module
source "$SCRIPT_DIR/modules/pwnagotchi_sync.sh"

# Synchronisation
if [ "$sync_type" = "all" ]; then
    sync_all >> "$LOG_DIR/autosync.log" 2>&1
else
    sync_incremental >> "$LOG_DIR/autosync.log" 2>&1
fi

echo "\$(date): Fin synchronisation automatique" >> "$LOG_DIR/autosync.log"
EOF
    
    chmod +x "$auto_sync_script"
    
    # Ajouter à cron
    local cron_line="0 */$interval * * * $auto_sync_script"
    
    # Vérifier si la ligne existe déjà
    if crontab -l 2>/dev/null | grep -q "wificybertools-autosync"; then
        # Remplacer la ligne existante
        crontab -l | sed "/wificybertools-autosync/c\\$cron_line" | crontab -
        success "Synchronisation automatique mise à jour"
    else
        # Ajouter nouvelle ligne
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        success "Synchronisation automatique configurée"
    fi
    
    echo "  ⏰ Intervalle: toutes les $interval heure(s)"
    echo "  🔄 Type: $sync_type"
    echo "  📜 Script: $auto_sync_script"
    echo "  📝 Log: $LOG_DIR/autosync.log"
}

sync_statistics() {
    header
    log "Statistiques de synchronisation..."
    
    echo -e "${CYAN}📊 Statistiques de synchronisation:${NC}"
    echo
    
    # Statistiques locales
    local local_files=$(find "$CAPTURES_DIR" -name "*.pcap*" | wc -l)
    local local_size=$(du -sh "$CAPTURES_DIR" 2>/dev/null | cut -f1)
    
    echo "📁 Répertoire local:"
    echo "  Fichiers: $local_files"
    echo "  Taille: $local_size"
    
    # Statistiques distantes
    echo
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o BatchMode=yes \
       "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" exit 2>/dev/null; then
        
        local remote_files=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
            "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' | wc -l" 2>/dev/null || echo "0")
        local remote_size=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
            "du -sh $PWNAGOTCHI_HANDSHAKE_DIR 2>/dev/null | cut -f1" || echo "Inconnu")
        local remote_space=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
            "df -h $PWNAGOTCHI_HANDSHAKE_DIR | tail -1 | awk '{print \$4}'" || echo "Inconnu")
        
        echo "📡 Pwnagotchi distant:"
        echo "  Fichiers: $remote_files"
        echo "  Taille: $remote_size"
        echo "  Espace libre: $remote_space"
        
        # Calcul de synchronisation
        local sync_ratio=0
        if [ "$remote_files" -gt 0 ]; then
            sync_ratio=$((local_files * 100 / remote_files))
        fi
        echo "  Taux de sync: $sync_ratio%"
        
    else
        echo "📡 Pwnagotchi: Non accessible"
    fi
    
    # Historique des synchronisations
    echo
    echo "📈 Historique récent:"
    if [ -f "$LOG_DIR/autosync.log" ]; then
        tail -10 "$LOG_DIR/autosync.log" | grep "Début\|Fin" | while read -r line; do
            echo "  $line"
        done
    else
        echo "  Aucun historique disponible"
    fi
    
    # Recommandations
    echo
    echo -e "${YELLOW}💡 Recommandations:${NC}"
    if [ "$local_files" -eq 0 ]; then
        echo "  • Effectuer une première synchronisation complète"
    elif [ "$sync_ratio" -lt 80 ]; then
        echo "  • Synchronisation incomplète, relancer une sync complète"
    else
        echo "  • Synchronisation à jour, utiliser le mode incrémental"
    fi
    
    if [ "$remote_space" != "Inconnu" ] && [[ "$remote_space" =~ ^[0-9]+[MK]$ ]]; then
        local space_num=$(echo "$remote_space" | sed 's/[MK]//')
        if [ "$space_num" -lt 100 ]; then
            echo "  • Espace faible sur Pwnagotchi, nettoyage recommandé"
        fi
    fi
}

update_sync_cache() {
    local cache_file="$LOG_DIR/sync_cache.txt"
    
    # Sauvegarder la liste des fichiers synchronisés avec timestamp
    find "$CAPTURES_DIR" -name "*.pcap*" -type f -exec basename {} \; | \
    while read -r filename; do
        echo "$(date +%s):$filename"
    done > "$cache_file"
    
    log "Cache de synchronisation mis à jour"
}

auto_sync() {
    # Fonction appelée par le système de synchronisation automatique
    sync_incremental
}
