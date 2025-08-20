#!/bin/bash

# ==============================================================================
# Module d'affichage des résultats WiFiCyberTools
# ==============================================================================

results_viewer_menu() {
    header
    echo -e "${BLUE}📊 VISUALISATION DES RÉSULTATS${NC}"

    local result_count=$(find "$RESULTS_DIR" -name "*.txt" 2>/dev/null | wc -l)
    echo -e "  📊 Fichiers de résultats: ${GREEN}$result_count${NC}"

    echo
    echo "1) Lister tous les résultats"
    echo "2) Afficher un résultat spécifique"
    echo "3) Statistiques globales"
    echo "4) Exporter les résultats"
    echo "5) Nettoyer les anciens résultats"
    echo "6) Retour au menu principal"
    echo

    read -p "Votre choix [1-6]: " choice

    case $choice in
        1) list_all_results ;;
        2) show_specific_result ;;
        3) show_global_stats ;;
        4) export_results ;;
        5) clean_old_results ;;
        6) return ;;
        *) warn "Option invalide" ;;
    esac

    read -p "Appuyez sur Entrée pour continuer..."
    results_viewer_menu
}

list_all_results() {
    header
    echo -e "${BLUE}📋 TOUS LES RÉSULTATS${NC}"
    echo

    local results=($(find "$RESULTS_DIR" -name "*.txt" -type f | sort -r))
    if [ ${#results[@]} -eq 0 ]; then
        warn "Aucun résultat trouvé"
        return
    fi

    for result in "${results[@]}"; do
        local name=$(basename "$result")
        local date=$(stat -c%y "$result" | cut -d' ' -f1)
        local count=$(wc -l < "$result")
        local status="🔓"
        if [ "$count" -eq 0 ]; then
            status="❌"
        fi
        echo "  $status $name - $date - $count mot(s) de passe"
        if [ "$count" -gt 0 ]; then
            echo "    Aperçu:"
            head -3 "$result" | while IFS=: read -r hash password; do
                echo "      🗝️  $password"
            done
        fi
        echo
    done
}

show_specific_result() {
    header
    echo -e "${BLUE}🔎 AFFICHER UN RÉSULTAT${NC}"
    echo

    local results=($(find "$RESULTS_DIR" -name "*.txt" -type f | sort -r))
    if [ ${#results[@]} -eq 0 ]; then
        warn "Aucun résultat trouvé"
        return
    fi

    echo "Résultats disponibles :"
    for i in "${!results[@]}"; do
        local name=$(basename "${results[$i]}")
        echo "  $((i+1))) $name"
    done

    read -p "Sélectionner un résultat [1-${#results[@]}]: " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#results[@]} ]; then
        local selected="${results[$((num-1))]}"
        echo
        echo -e "${CYAN}Contenu de $selected:${NC}"
        cat "$selected" | while IFS=: read -r hash password; do
            echo "  🗝️  $password"
        done
    else
        warn "Sélection invalide"
    fi
}

show_global_stats() {
    header
    echo -e "${BLUE}📈 STATISTIQUES GLOBALES${NC}"
    echo

    local total_results=$(find "$RESULTS_DIR" -name "*.txt" | wc -l)
    local successful_attacks=0
    local total_passwords=0

    # Compter les attaques réussies
    find "$RESULTS_DIR" -name "*.txt" -type f | while IFS= read -r file; do
        local count=$(wc -l < "$file")
        if [ "$count" -gt 0 ]; then
            successful_attacks=$((successful_attacks + 1))
            total_passwords=$((total_passwords + count))
        fi
    done

    echo "📊 Résumé des attaques:"
    echo "  • Total d'attaques: $total_results"
    echo "  • Attaques réussies: $successful_attacks"
    if [ "$total_results" -gt 0 ]; then
        echo "  • Taux de succès: $((successful_attacks * 100 / total_results))%"
    else
        echo "  • Taux de succès: 0%"
    fi
    echo "  • Mots de passe totaux: $total_passwords"
    echo

    # Top des mots de passe les plus fréquents
    if [ "$total_passwords" -gt 0 ]; then
        echo "🏆 Top des mots de passe trouvés:"
        find "$RESULTS_DIR" -name "*.txt" -exec cat {} \; | \
        cut -d: -f2 | sort | uniq -c | sort -nr | head -10 | \
        while read count password; do
            echo "  $count× $password"
        done
    fi
}

export_results() {
    header
    echo -e "${BLUE}⬇️  EXPORTER LES RÉSULTATS${NC}"
    local export_file="$RESULTS_DIR/export_all_results_$(date +%Y%m%d_%H%M%S).txt"
    find "$RESULTS_DIR" -name "*.txt" -type f -exec cat {} \; | cut -d: -f2 | sort | uniq > "$export_file"
    success "Export réalisé : $export_file"
    echo "Contenu :"
    head -10 "$export_file"
    echo ...
}

clean_old_results() {
    header
    echo -e "${RED}🧹 NETTOYER LES ANCIENS RÉSULTATS${NC}"
    echo
    read -p "Supprimer tous les résultats de plus de combien de jours ? [30]: " days
    days=${days:-30}
    local to_delete=$(find "$RESULTS_DIR" -name "*.txt" -mtime +"$days" -type f)
    local delete_count=$(echo "$to_delete" | wc -l)
    if [ "$delete_count" -eq 0 ]; then
        success "Aucun résultat ancien à supprimer."
        return
    fi
    echo -e "${YELLOW}$delete_count résultat(s) vont être supprimé(s). Continuer ? [y/N]:${NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        echo "$to_delete" | xargs rm -f
        success "$delete_count résultat(s) supprimé(s)"
    else
        echo "Suppression annulée."
    fi
}
