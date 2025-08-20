#!/bin/bash

# ==============================================================================
# Module gestionnaire des wordlists WiFiCyberTools
# ==============================================================================

wordlist_manager_menu() {
    header
    echo -e "${BLUE}📚 GESTION DES WORDLISTS${NC}"
    
    local wordlist_count=$(find "$WORDLISTS_DIR" -name "*.txt" 2>/dev/null | wc -l)
    echo -e "  📚 Wordlists installées: ${GREEN}$wordlist_count${NC}"
    
    echo
    echo "1) Télécharger wordlists populaires"
    echo "2) Installer wordlist par URL"
    echo "3) Lister wordlists disponibles"
    echo "4) Supprimer une wordlist"
    echo "5) Créer une wordlist personnalisée"
    echo "6) Optimiser wordlists existantes"
    echo "7) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-7]: " choice
    
    case $choice in
        1) download_popular_wordlists ;;
        2) install_wordlist_by_url ;;
        3) list_wordlists ;;
        4) remove_wordlists ;;
        5) create_custom_wordlist ;;
        6) optimize_wordlists ;;
        7) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    wordlist_manager_menu
}

download_popular_wordlists() {
    header
    log "Téléchargement des wordlists populaires..."
    
    source "$SCRIPT_DIR/config/wordlists.conf"
    
    declare -A wordlists=(
        ["rockyou.txt"]="$ROCKYOU_URL"
        ["wifi-wpa.txt"]="$WIFI_WPA_URL"
        ["darkweb2017.txt"]="$DARKWEB_URL"
        ["french-passwords.txt"]="$FRENCH_URL"
        ["probable-v2.txt"]="$PROBABLE_V2_URL"
    )

    mkdir -p "$WORDLISTS_DIR"

    for name in "${!wordlists[@]}"; do
        local url="${wordlists[$name]}"
        local outfile="$WORDLISTS_DIR/$name"

        if [ -f "$outfile" ]; then
            warn "$name existe déjà, ignorée"
            continue
        fi

        echo "Téléchargement $name..."
        if curl -L -o "$outfile" "$url" --connect-timeout 30 --max-time 300; then
            echo "Téléchargée: $name"
            # Décompresser si nécessaire
            if [[ "$outfile" == *.gz ]]; then
                gunzip -f "$outfile"
                echo "Décompressée: $name"
            fi
        else
            error "Échec téléchargement: $name"
            rm -f "$outfile"
        fi
    done
}

install_wordlist_by_url() {
    header
    echo -e "${BLUE}📥 INSTALLER WORDLIST PAR URL${NC}"
    read -p "URL de la wordlist: " url
    [ -z "$url" ] && { warn "URL vide"; return 1; }
    read -p "Nom du fichier (optionnel): " filename
    if [ -z "$filename" ]; then
        filename=$(basename "$url")
        [[ "$filename" != *.txt ]] && filename="${filename}.txt"
    fi
    local outpath="$WORDLISTS_DIR/$filename"
    mkdir -p "$WORDLISTS_DIR"
    echo "Téléchargement de $filename..."
    if curl -L -o "$outpath" "$url" --connect-timeout 30; then
        echo "Téléchargement réussi : $filename"
    else
        error "Échec téléchargement"
        rm -f "$outpath"
    fi
}

list_wordlists() {
    header
    echo -e "${BLUE}📋 WORDLISTS DISPONIBLES${NC}"
    mkdir -p "$WORDLISTS_DIR"
    local wordlists=($(find "$WORDLISTS_DIR" -name "*.txt" -type f | sort))
    if [ ${#wordlists[@]} -eq 0 ]; then
        warn "Aucune wordlist trouvée"
        return
    fi
    for wl in "${wordlists[@]}"; do
        local name=$(basename "$wl")
        local size=$(wc -l < "$wl" 2>/dev/null || echo "?")
        echo "  📝 $name - $size lignes"
    done
}

remove_wordlists() {
    header
    echo -e "${RED}🗑️ SUPPRIMER UNE WORDLIST${NC}"
    
    local wordlists=($(find "$WORDLISTS_DIR" -name "*.txt" -type f))
    if [ ${#wordlists[@]} -eq 0 ]; then
        warn "Aucune wordlist à supprimer"
        return
    fi
    
    echo "Wordlists disponibles:"
    for i in "${!wordlists[@]}"; do
        echo "  $((i+1))) $(basename "${wordlists[$i]}")"
    done
    
    read -p "Numéro à supprimer: " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#wordlists[@]} ]; then
        rm -f "${wordlists[$((num-1))]}"
        success "Wordlist supprimée"
    else
        warn "Sélection invalide"
    fi
}

create_custom_wordlist() {
    header
    echo -e "${BLUE}✍️ CRÉER UNE WORDLIST PERSONNALISÉE${NC}"
    read -p "Nom du fichier (sans extension): " name
    [ -z "$name" ] && { warn "Nom vide"; return; }
    read -p "Entrez les mots (séparés par espaces) : " words
    mkdir -p "$WORDLISTS_DIR"
    local filepath="$WORDLISTS_DIR/${name}.txt"
    echo "$words" | tr ' ' '\n' > "$filepath"
    success "Wordlist personnalisée créée: $filepath"
}

optimize_wordlists() {
    header
    echo -e "${BLUE}✨ OPTIMISER LES WORDLISTS${NC}"
    echo "Cette opération supprimera les doublons et lignes vides."
    read -p "Confirmer? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log "Optimisation annulée"
        return
    fi
    
    local optimized=0
    for wl in "$WORDLISTS_DIR"/*.txt; do
        [ -e "$wl" ] || continue
        local lines_before=$(wc -l < "$wl")
        # Nettoyage
        awk '!x[$0]++' "$wl" | sed '/^\s*$/d' > /tmp/wl_optimized.txt
        mv /tmp/wl_optimized.txt "$wl"
        local lines_after=$(wc -l < "$wl")
        if [ "$lines_after" -lt "$lines_before" ]; then
            echo "Optimisé: $(basename "$wl") ($lines_before → $lines_after lignes)"
            optimized=$((optimized + 1))
        fi
    done
    
    if [ "$optimized" -eq 0 ]; then
        warn "Aucune wordlist nécessitant optimisation"
    else
        success "Optimisation effectuée sur $optimized wordlist(s)"
    fi
}
