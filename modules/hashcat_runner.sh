#!/bin/bash

# ==============================================================================
# Module Hashcat Runner WiFiCyberTools
# ==============================================================================

hashcat_runner_menu() {
    header
    echo -e "${BLUE}💥 ATTAQUES HASHCAT${NC}"
    
    # Status des fichiers convertis
    local converted_count=$(find "$CONVERTED_DIR" -name "*.hc22000" 2>/dev/null | wc -l)
    local wordlist_count=$(find "$WORDLISTS_DIR" -name "*.txt" 2>/dev/null | wc -l)
    
    echo -e "  🔄 Fichiers hash disponibles: ${GREEN}$converted_count${NC}"
    echo -e "  📚 Wordlists disponibles: ${GREEN}$wordlist_count${NC}"
    
    # Status GPU
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1)
        local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1 | tr -d '%')
        echo -e "  🌡️  GPU: ${gpu_temp}°C (${gpu_util}% util.)"
    fi
    
    echo
    echo "1) Attaque automatique (wordlists + règles)"
    echo "2) Attaque par dictionnaire simple"
    echo "3) Attaque par masque (brute force)"
    echo "4) Attaque hybride (dictionnaire + masque)"
    echo "5) Reprendre une session interrompue"
    echo "6) Benchmark GPU"
    echo "7) Gestion des sessions"
    echo "8) Configuration avancée Hashcat"
    echo "9) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-9]: " choice
    
    case $choice in
        1) auto_attack ;;
        2) dictionary_attack ;;
        3) mask_attack ;;
        4) hybrid_attack ;;
        5) resume_session ;;
        6) gpu_benchmark ;;
        7) session_manager ;;
        8) advanced_config ;;
        9) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    hashcat_runner_menu
}

auto_attack() {
    header
    log "Sélection du fichier hash pour l'attaque automatique..."
    
    # Lister les fichiers hash disponibles
    local hash_files=($(find "$CONVERTED_DIR" -name "*.hc22000" -type f))
    local count=${#hash_files[@]}
    
    if [ "$count" -eq 0 ]; then
        error "Aucun fichier hash trouvé dans $CONVERTED_DIR"
        echo "Utilisez d'abord le module 'Validation des handshakes' pour convertir vos captures"
        return 1
    fi
    
    # Affichage des fichiers avec détails
    echo -e "${CYAN}Fichiers hash disponibles:${NC}"
    for i in "${!hash_files[@]}"; do
        local file="${hash_files[i]}"
        local basename=$(basename "$file" .hc22000)
        local hash_count=$(wc -l < "$file")
        local essid=""
        
        # Récupérer l'ESSID si disponible
        local essid_file="$CONVERTED_DIR/${basename}.main_essid"
        if [ -f "$essid_file" ]; then
            essid=" ($(cat "$essid_file"))"
        fi
        
        echo "  $((i+1))) $basename - $hash_count hash(es)$essid"
    done
    
    echo
    read -p "Sélectionnez un fichier [1-$count]: " file_choice
    
    if ! [[ "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -lt 1 ] || [ "$file_choice" -gt "$count" ]; then
        error "Sélection invalide"
        return 1
    fi
    
    local selected_file="${hash_files[$((file_choice-1))]}"
    local basename=$(basename "$selected_file" .hc22000)
    
    log "Fichier sélectionné: $basename"
    
    # Lancement de l'attaque automatique
    run_auto_attack "$selected_file" "$basename"
}

run_auto_attack() {
    local hash_file="$1"
    local basename="$2"
    local session_name="auto_${basename}_$(date +%Y%m%d_%H%M%S)"
    
    log "Lancement attaque automatique: $session_name"
    
    mkdir -p "$RESULTS_DIR"
    
    # Recherche des wordlists dans l'ordre de priorité
    local wordlists=()
    
    # 1. Wordlists WiFi spécialisées
    local wifi_wordlists=($(find "$WORDLISTS_DIR" -name "*wifi*" -o -name "*wpa*" -type f))
    for wl in "${wifi_wordlists[@]}"; do
        wordlists+=("$wl")
    done
    
    # 2. Wordlists générales populaires
    local common_wordlists=($(find "$WORDLISTS_DIR" -name "*rockyou*" -o -name "*common*" -o -name "*top*" -type f))
    for wl in "${common_wordlists[@]}"; do
        wordlists+=("$wl")
    done
    
    # 3. Autres wordlists
    local other_wordlists=($(find "$WORDLISTS_DIR" -name "*.txt" -type f))
    for wl in "${other_wordlists[@]}"; do
        if [[ ! " ${wordlists[@]} " =~ " $wl " ]]; then
            wordlists+=("$wl")
        fi
    done
    
    if [ ${#wordlists[@]} -eq 0 ]; then
        warn "Aucune wordlist trouvée, génération d'une wordlist de base..."
        create_basic_wordlist
        wordlists=("$WORDLISTS_DIR/basic.txt")
    fi
    
    # Limiter à 3 wordlists pour éviter les attaques trop longues
    wordlists=("${wordlists[@]:0:3}")
    
    # Étape 1: Attaques par dictionnaire simple
    for wordlist in "${wordlists[@]}"; do
        local wordlist_name=$(basename "$wordlist" .txt)
        log "Test avec wordlist: $wordlist_name"
        
        # Vérification de la taille de la wordlist
        local wordlist_size=$(wc -l < "$wordlist" 2>/dev/null || echo "0")
        log "Taille wordlist: $wordlist_size mots"
        
        if [ "$wordlist_size" -eq 0 ]; then
            warn "Wordlist vide, ignorée: $wordlist_name"
            continue
        fi
        
        # Commande Hashcat optimisée
        local result_file="$RESULTS_DIR/${basename}_${wordlist_name}_$(date +%H%M%S).txt"
        local cmd=(
            "hashcat"
            "-a" "0"                    # Attack mode: dictionary
            "-m" "22000"               # Hash mode: WPA-PBKDF2-PMKID+EAPOL
            "-w" "$HASHCAT_WORKLOAD"   # Workload profile
            "--status"                 # Show status
            "--status-timer" "30"      # Status every 30s
            "--hwmon-temp-abort" "$GPU_TEMP_LIMIT"
            "--session" "${session_name}_${wordlist_name}"
            "--outfile" "$result_file"
            "--outfile-format" "2"     # Format: hash:password
            "--force"                  # Force mode si problèmes GPU
        )
        
        # Ajout des optimisations si GPU disponible
        if command -v nvidia-smi >/dev/null 2>&1; then
            cmd+=("--optimized-kernel-enable")
        fi
        
        cmd+=("$hash_file" "$wordlist")
        
        log "Commande: ${cmd[*]}"
        
        # Exécution avec timeout
        local start_time=$(date +%s)
        if timeout "$HASHCAT_TIMEOUT" "${cmd[@]}" 2>&1 | tee "$LOG_DIR/hashcat_${session_name}_${wordlist_name}.log"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            # Vérifier les résultats
            if [ -s "$result_file" ]; then
                local found_count=$(wc -l < "$result_file")
                success "$found_count mot(s) de passe trouvé(s) avec $wordlist_name en ${duration}s!"
                
                # Afficher les résultats
                echo -e "${GREEN}🎯 MOTS DE PASSE TROUVÉS:${NC}"
                while IFS=: read -r hash password; do
                    echo "  🔓 $password"
                done < "$result_file"
                
                # Créer un résumé
                create_attack_summary "$basename" "$wordlist_name" "$found_count" "$duration" "$result_file"
                
                log "Attaque réussie, arrêt des tests supplémentaires"
                return 0
            else
                log "Aucun résultat avec $wordlist_name (durée: ${duration}s)"
            fi
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            warn "Timeout ou interruption sur wordlist: $wordlist_name (durée: ${duration}s)"
        fi
    done
    
    # Étape 2: Attaque avec règles si pas de résultats
    if [ ${#wordlists[@]} -gt 0 ]; then
        log "Attaque avec règles de transformation..."
        
        local best_wordlist="${wordlists[0]}"
        local rules_files=($(find /usr/share/hashcat/rules -name "*.rule" 2>/dev/null | head -2))
        
        if [ ${#rules_files[@]} -eq 0 ]; then
            # Créer des règles de base
            mkdir -p "$DATA_DIR/rules"
            create_basic_rules "$DATA_DIR/rules/basic.rule"
            rules_files=("$DATA_DIR/rules/basic.rule")
        fi
        
        for rules_file in "${rules_files[@]}"; do
            local rules_name=$(basename "$rules_file" .rule)
            log "Test avec règles: $rules_name"
            
            local result_file="$RESULTS_DIR/${basename}_${rules_name}_$(date +%H%M%S).txt"
            local cmd_rules=(
                "hashcat"
                "-a" "0"
                "-m" "22000"
                "-w" "$HASHCAT_WORKLOAD"
                "-r" "$rules_file"
                "--status"
                "--status-timer" "30"
                "--hwmon-temp-abort" "$GPU_TEMP_LIMIT"
                "--session" "${session_name}_rules_${rules_name}"
                "--outfile" "$result_file"
                "--outfile-format" "2"
                "--force"
                "$hash_file"
                "$best_wordlist"
            )
            
            local start_time=$(date +%s)
            if timeout "$HASHCAT_TIMEOUT" "${cmd_rules[@]}" 2>&1 | tee "$LOG_DIR/hashcat_${session_name}_${rules_name}.log"; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                if [ -s "$result_file" ]; then
                    local found_count=$(wc -l < "$result_file")
                    success "$found_count mot(s) de passe trouvé(s) avec les règles $rules_name!"
                    
                    echo -e "${GREEN}🎯 MOTS DE PASSE TROUVÉS (avec règles):${NC}"
                    while IFS=: read -r hash password; do
                        echo "  🔓 $password"
                    done < "$result_file"
                    
                    create_attack_summary "$basename" "rules_$rules_name" "$found_count" "$duration" "$result_file"
                    return 0
                fi
            else
                warn "Timeout avec règles: $rules_name"
            fi
        done
    fi
    
    warn "Aucun mot de passe trouvé avec les méthodes automatiques"
    log "Essayez une attaque par masque ou des wordlists plus importantes"
    
    # Créer un rapport d'échec
    create_failure_report "$basename" "$session_name"
}

create_basic_wordlist() {
    local basic_file="$WORDLISTS_DIR/basic.txt"
    
    log "Création d'une wordlist de base..."
    
    cat > "$basic_file" << 'EOF'
password
123456
password123
admin
root
qwerty
abc123
Password1
welcome
login
wifipassword
internet
wireless
network
routeur
freebox
livebox
bbox
sfr
orange
bouygues
12345678
87654321
motdepasse
azerty
1234567890
wifi
pass
user
test
guest
demo
administrator
password1
123123
111111
000000
1qaz2wsx
qwertyuiop
abcd1234
letmein
trustno1
monkey
dragon
EOF
    
    success "Wordlist de base créée: $basic_file ($(wc -l < "$basic_file") mots)"
}

create_basic_rules() {
    local rules_file="$1"
    
    cat > "$rules_file" << 'EOF'
:
l
u
c
$1
$2
$3
$!
$@
$#
^1
^2
^3
^!
^@
^#
r
d
f
}
{
$1$2
$1$3
$!$!
$@$#
c$1
c$2
c$!
u$1
u$2
u$!
l$1
l$2
l$!
EOF
    
    log "Règles de base créées: $rules_file"
}

create_attack_summary() {
    local target="$1"
    local method="$2"
    local found_count="$3"
    local duration="$4"
    local result_file="$5"
    
    local summary_file="$RESULTS_DIR/summary_${target}_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$summary_file" << EOF
{
    "attack_summary": {
        "target": "$target",
        "method": "$method",
        "timestamp": "$(date -Iseconds)",
        "duration_seconds": $duration,
        "passwords_found": $found_count,
        "result_file": "$result_file",
        "success": true
    },
    "passwords": [
EOF
    
    # Ajouter les mots de passe trouvés
    local first=true
    while IFS=: read -r hash password; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$summary_file"
        fi
        echo -n "        \"$password\"" >> "$summary_file"
    done < "$result_file"
    
    cat >> "$summary_file" << EOF

    ]
}
EOF
    
    log "Résumé sauvegardé: $summary_file"
}

create_failure_report() {
    local target="$1"
    local session_name="$2"
    
    local report_file="$RESULTS_DIR/failure_${target}_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$report_file" << EOF
{
    "attack_failure": {
        "target": "$target",
        "session": "$session_name",
        "timestamp": "$(date -Iseconds)",
        "success": false,
        "recommendations": [
            "Essayer une attaque par masque",
            "Utiliser des wordlists plus importantes",
            "Tenter une attaque hybride",
            "Vérifier que le handshake est correct"
        ]
    }
}
EOF
    
    log "Rapport d'échec sauvegardé: $report_file"
}

dictionary_attack() {
    header
    log "Configuration attaque par dictionnaire..."
    
    # Sélection du fichier hash
    select_hash_file
    if [ -z "$SELECTED_HASH_FILE" ]; then
        return 1
    fi
    
    # Sélection de la wordlist
    select_wordlist
    if [ -z "$SELECTED_WORDLIST" ]; then
        return 1
    fi
    
    local basename=$(basename "$SELECTED_HASH_FILE" .hc22000)
    local wordlist_name=$(basename "$SELECTED_WORDLIST" .txt)
    
    log "Configuration:"
    echo "  🎯 Cible: $basename"
    echo "  📚 Wordlist: $wordlist_name"
    echo
    
    read -p "Confirmer l'attaque? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log "Attaque annulée"
        return 0
    fi
    
    # Lancement de l'attaque
    run_dictionary_attack "$SELECTED_HASH_FILE" "$SELECTED_WORDLIST" "$basename" "$wordlist_name"
}

run_dictionary_attack() {
    local hash_file="$1"
    local wordlist="$2"
    local basename="$3"
    local wordlist_name="$4"
    
    local session_name="dict_${basename}_$(date +%Y%m%d_%H%M%S)"
    local result_file="$RESULTS_DIR/${basename}_${wordlist_name}_$(date +%H%M%S).txt"
    
    log "Démarrage attaque par dictionnaire..."
    
    local cmd=(
        "hashcat"
        "-a" "0"
        "-m" "22000"
        "-w" "$HASHCAT_WORKLOAD"
        "--status"
        "--status-timer" "15"
        "--hwmon-temp-abort" "$GPU_TEMP_LIMIT"
        "--session" "$session_name"
        "--outfile" "$result_file"
        "--outfile-format" "2"
        "--force"
        "$hash_file"
        "$wordlist"
    )
    
    log "Exécution: ${cmd[*]}"
    
    local start_time=$(date +%s)
    "${cmd[@]}" 2>&1 | tee "$LOG_DIR/hashcat_$session_name.log"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Analyse des résultats
    if [ -s "$result_file" ]; then
        local found_count=$(wc -l < "$result_file")
        success "$found_count mot(s) de passe trouvé(s) en ${duration}s!"
        
        echo -e "${GREEN}🎯 RÉSULTATS:${NC}"
        cat "$result_file" | while IFS=: read -r hash password; do
            echo "  🔓 $password"
        done
        
        create_attack_summary "$basename" "dictionary_$wordlist_name" "$found_count" "$duration" "$result_file"
    else
        warn "Aucun mot de passe trouvé"
        create_failure_report "$basename" "$session_name"
    fi
}

select_hash_file() {
    local hash_files=($(find "$CONVERTED_DIR" -name "*.hc22000" -type f))
    local count=${#hash_files[@]}
    
    if [ "$count" -eq 0 ]; then
        error "Aucun fichier hash trouvé"
        return 1
    fi
    
    echo "Fichiers hash disponibles:"
    for i in "${!hash_files[@]}"; do
        local file="${hash_files[i]}"
        local basename=$(basename "$file" .hc22000)
        local hash_count=$(wc -l < "$file")
        echo "  $((i+1))) $basename ($hash_count hash(es))"
    done
    
    echo
    read -p "Sélectionnez un fichier [1-$count]: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
        SELECTED_HASH_FILE="${hash_files[$((choice-1))]}"
    else
        error "Sélection invalide"
        return 1
    fi
}

select_wordlist() {
    local wordlists=($(find "$WORDLISTS_DIR" -name "*.txt" -type f))
    local count=${#wordlists[@]}
    
    if [ "$count" -eq 0 ]; then
        error "Aucune wordlist trouvée"
        return 1
    fi
    
    echo "Wordlists disponibles:"
    for i in "${!wordlists[@]}"; do
        local file="${wordlists[i]}"
        local name=$(basename "$file" .txt)
        local size=$(wc -l < "$file" 2>/dev/null || echo "?")
        echo "  $((i+1))) $name ($size mots)"
    done
    
    echo
    read -p "Sélectionnez une wordlist [1-$count]: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
        SELECTED_WORDLIST="${wordlists[$((choice-1))]}"
    else
        error "Sélection invalide"
        return 1
    fi
}

mask_attack() {
    header
    echo -e "${BLUE}🎲 ATTAQUE PAR MASQUE${NC}"
    echo
    echo "Masques WiFi courants:"
    echo "1) ?d?d?d?d?d?d?d?d (8 chiffres)"
    echo "2) ?l?l?l?l?l?l?l?l (8 lettres minuscules)"
    echo "3) ?u?l?l?l?l?l?d?d (1 maj + 5 min + 2 chiffres)"
    echo "4) wifi?d?d?d?d (wifi + 4 chiffres)"
    echo "5) Masque personnalisé"
    echo
    
    read -p "Votre choix [1-5]: " mask_choice
    
    local mask=""
    case $mask_choice in
        1) mask="?d?d?d?d?d?d?d?d" ;;
        2) mask="?l?l?l?l?l?l?l?l" ;;
        3) mask="?u?l?l?l?l?l?d?d" ;;
        4) mask="wifi?d?d?d?d" ;;
        5) 
            read -p "Entrez votre masque: " custom_mask
            mask="$custom_mask"
            ;;
        *) 
            error "Choix invalide"
            return 1
            ;;
    esac
    
    if [ -z "$mask" ]; then
        error "Masque vide"
        return 1
    fi
    
    # Sélection du fichier hash
    select_hash_file
    if [ -z "$SELECTED_HASH_FILE" ]; then
        return 1
    fi
    
    run_mask_attack "$SELECTED_HASH_FILE" "$mask"
}

run_mask_attack() {
    local hash_file="$1"
    local mask="$2"
    local basename=$(basename "$hash_file" .hc22000)
    
    local session_name="mask_${basename}_$(date +%Y%m%d_%H%M%S)"
    local result_file="$RESULTS_DIR/${basename}_mask_$(date +%H%M%S).txt"
    
    log "Démarrage attaque par masque: $mask"
    
    # Estimation du temps
    log "Calcul des combinaisons possibles..."
    
    local cmd=(
        "hashcat"
        "-a" "3"                    # Attack mode: brute force
        "-m" "22000"
        "-w" "$HASHCAT_WORKLOAD"
        "--status"
        "--status-timer" "60"       # Status plus espacé pour brute force
        "--hwmon-temp-abort" "$GPU_TEMP_LIMIT"
        "--session" "$session_name"
        "--outfile" "$result_file"
        "--outfile-format" "2"
        "--force"
        "$hash_file"
        "$mask"
    )
    
    log "Exécution: ${cmd[*]}"
    warn "ATTENTION: Les attaques par masque peuvent être très longues!"
    
    read -p "Continuer? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log "Attaque annulée"
        return 0
    fi
    
    local start_time=$(date +%s)
    "${cmd[@]}" 2>&1 | tee "$LOG_DIR/hashcat_$session_name.log"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Analyse des résultats
    if [ -s "$result_file" ]; then
        local found_count=$(wc -l < "$result_file")
        success "$found_count mot(s) de passe trouvé(s) avec masque en ${duration}s!"
        
        echo -e "${GREEN}🎯 RÉSULTATS:${NC}"
        cat "$result_file" | while IFS=: read -r hash password; do
            echo "  🔓 $password"
        done
    else
        warn "Aucun mot de passe trouvé avec ce masque"
    fi
}

hybrid_attack() {
    header
    log "Attaque hybride (dictionnaire + masque)..."
    echo "Module en développement"
}

resume_session() {
    header
    log "Reprise de session..."
    
    # Recherche des sessions existantes
    local restore_files=($(find . -name "*.restore" 2>/dev/null))
    
    if [ ${#restore_files[@]} -eq 0 ]; then
        warn "Aucune session à reprendre"
        return 1
    fi
    
    echo "Sessions disponibles:"
    for i in "${!restore_files[@]}"; do
        local file="${restore_files[i]}"
        local session_name=$(basename "$file" .restore)
        local date=$(stat -f%Sm "$file" 2>/dev/null || stat -c%y "$file" | cut -d' ' -f1)
        echo "  $((i+1))) $session_name - $date"
    done
    
    echo
    read -p "Sélectionnez une session [1-${#restore_files[@]}]: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#restore_files[@]} ]; then
        local selected_restore="${restore_files[$((choice-1))]}"
        local session_name=$(basename "$selected_restore" .restore)
        
        log "Reprise de la session: $session_name"
        hashcat --session "$session_name" --restore
    else
        error "Sélection invalide"
    fi
}

gpu_benchmark() {
    header
    log "Benchmark GPU pour les modes de hash courants..."
    
    # Test sur différents modes de hash
    local modes=("0" "1000" "2500" "22000")
    local mode_names=("MD5" "NTLM" "WPA/WPA2" "WPA3/22000")
    
    echo -e "${CYAN}Benchmark GPU:${NC}"
    echo
    
    for i in "${!modes[@]}"; do
        local mode="${modes[i]}"
        local name="${mode_names[i]}"
        
        echo "🧪 Test $name (mode $mode):"
        if timeout 60 hashcat -b -m "$mode" --quiet 2>/dev/null | grep "Speed"; then
            echo "  ✅ Test réussi"
        else
            echo "  ❌ Échec du test"
        fi
        echo
    done
    
    # Test avec différents workload profiles
    echo -e "${CYAN}Test des profils de workload:${NC}"
    for profile in 1 2 3 4; do
        echo "Profil $profile:"
        if timeout 30 hashcat -b -m 22000 -w "$profile" --quiet 2>/dev/null | grep "Speed"; then
            echo "  ✅ Profil $profile fonctionnel"
        else
            echo "  ❌ Profil $profile non supporté"
        fi
    done
}

session_manager() {
    header
    echo -e "${BLUE}📋 GESTION DES SESSIONS${NC}"
    echo "Module en développement - gestion des sessions Hashcat"
    echo
    echo "Fonctionnalités prévues:"
    echo "  • Liste des sessions actives"
    echo "  • Pause/reprise des sessions"
    echo "  • Suppression des sessions"
    echo "  • Monitoring en temps réel"
}

advanced_config() {
    header
    echo -e "${BLUE}⚙️ CONFIGURATION AVANCÉE HASHCAT${NC}"
    echo
    echo "Configuration actuelle:"
    echo "  Workload Profile: $HASHCAT_WORKLOAD"
    echo "  Timeout: $HASHCAT_TIMEOUT secondes"
    echo "  Limite température: $GPU_TEMP_LIMIT°C"
    echo
    echo "1) Modifier le workload profile"
    echo "2) Modifier le timeout"
    echo "3) Modifier la limite de température"
    echo "4) Test des paramètres"
    echo "5) Retour"
    echo
    
    read -p "Votre choix [1-5]: " config_choice
    
    case $config_choice in
        1) 
            read -p "Nouveau workload profile [1-4]: " new_workload
            if [[ "$new_workload" =~ ^[1-4]$ ]]; then
                sed -i "s/HASHCAT_WORKLOAD=.*/HASHCAT_WORKLOAD=$new_workload/" "$CONFIG_FILE"
                success "Workload profile mis à jour: $new_workload"
            fi
            ;;
        2)
            read -p "Nouveau timeout en secondes [$HASHCAT_TIMEOUT]: " new_timeout
            if [[ "$new_timeout" =~ ^[0-9]+$ ]]; then
                sed -i "s/HASHCAT_TIMEOUT=.*/HASHCAT_TIMEOUT=$new_timeout/" "$CONFIG_FILE"
                success "Timeout mis à jour: $new_timeout secondes"
            fi
            ;;
        3)
            read -p "Nouvelle limite température [$GPU_TEMP_LIMIT]: " new_temp
            if [[ "$new_temp" =~ ^[0-9]+$ ]]; then
                sed -i "s/GPU_TEMP_LIMIT=.*/GPU_TEMP_LIMIT=$new_temp/" "$CONFIG_FILE"
                success "Limite température mise à jour: $new_temp°C"
            fi
            ;;
        4)
            log "Test des paramètres..."
            timeout 30 hashcat -b -m 22000 -w "$HASHCAT_WORKLOAD" --quiet || warn "Test échoué"
            ;;
        5)
            return
            ;;
    esac
}

run_attack() {
    local hash_file="$1"
    
    if [ ! -f "$hash_file" ]; then
        error "Fichier hash non trouvé: $hash_file"
        return 1
    fi
    
    SELECTED_HASH_FILE="$hash_file"
    auto_attack
}
