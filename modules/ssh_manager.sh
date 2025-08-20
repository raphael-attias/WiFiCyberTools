#!/bin/bash

# ==============================================================================
# Module de gestion SSH WiFiCyberTools
# ==============================================================================

ssh_manager_menu() {
    header
    echo -e "${BLUE}🔑 GESTION DES CLÉS SSH${NC}"
    echo
    
    # Status SSH
    if [ -f "$SSH_KEY_PATH" ]; then
        echo -e "  🔑 Clé SSH: ${GREEN}Configurée${NC} ($SSH_KEY_PATH)"
        
        # Test connectivité
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=3 -o BatchMode=yes \
           "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" exit 2>/dev/null; then
            echo -e "  🌐 Connexion: ${GREEN}Fonctionnelle${NC}"
        else
            echo -e "  🌐 Connexion: ${RED}Échec${NC}"
        fi
    else
        echo -e "  🔑 Clé SSH: ${RED}Non configurée${NC}"
    fi
    
    echo
    echo "1) Générer une nouvelle clé SSH"
    echo "2) Installer la clé sur le Pwnagotchi"
    echo "3) Tester la connexion SSH"
    echo "4) Supprimer les clés SSH"
    echo "5) Configuration manuelle SSH"
    echo "6) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-6]: " choice
    
    case $choice in
        1) generate_ssh_key ;;
        2) install_ssh_key ;;
        3) test_ssh_connection ;;
        4) remove_ssh_keys ;;
        5) manual_ssh_config ;;
        6) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    ssh_manager_menu
}

generate_ssh_key() {
    header
    log "Génération d'une nouvelle clé SSH..."
    
    # Créer le répertoire .ssh
    mkdir -p "$(dirname "$SSH_KEY_PATH")"
    
    # Supprimer l'ancienne clé si elle existe
    if [ -f "$SSH_KEY_PATH" ]; then
        warn "Suppression de l'ancienne clé..."
        rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    fi
    
    # Générer la nouvelle clé
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "wificybertools-$(date +%Y%m%d)"
    
    success "Clé SSH générée: $SSH_KEY_PATH"
    
    # Proposer l'installation automatique
    echo
    read -p "Installer automatiquement sur le Pwnagotchi? [y/N]: " install_now
    if [[ "$install_now" =~ ^[Yy] ]]; then
        install_ssh_key
    fi
}

install_ssh_key() {
    header
    log "Installation de la clé SSH sur le Pwnagotchi..."
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        error "Aucune clé SSH trouvée. Générez d'abord une clé."
        return 1
    fi
    
    # Test de connectivité
    if ! ping -c 1 -W 3 "$PWNAGOTCHI_IP" >/dev/null 2>&1; then
        error "Pwnagotchi non accessible à $PWNAGOTCHI_IP"
        return 1
    fi
    
    # Installation avec ssh-copy-id
    if command -v sshpass >/dev/null 2>&1; then
        log "Installation avec ssh-copy-id..."
        if sshpass -p "$PWNAGOTCHI_PASS" ssh-copy-id -i "${SSH_KEY_PATH}.pub" \
           -o StrictHostKeyChecking=no "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" 2>/dev/null; then
            success "Clé installée avec succès"
        else
            warn "Échec ssh-copy-id, tentative manuelle..."
            install_ssh_key_manual
        fi
    else
        install_ssh_key_manual
    fi
    
    # Test de la nouvelle configuration
    test_ssh_connection
}

install_ssh_key_manual() {
    log "Installation manuelle de la clé SSH..."
    
    local pub_key_content=$(cat "${SSH_KEY_PATH}.pub")
    
    if command -v sshpass >/dev/null 2>&1; then
        sshpass -p "$PWNAGOTCHI_PASS" ssh -o StrictHostKeyChecking=no \
            "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
            "mkdir -p ~/.ssh && echo '$pub_key_content' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
        success "Clé installée manuellement"
    else
        error "sshpass non disponible. Installation manuelle requise:"
        echo
        echo "1. Connectez-vous au Pwnagotchi:"
        echo "   ssh $PWNAGOTCHI_USER@$PWNAGOTCHI_IP"
        echo
        echo "2. Exécutez ces commandes:"
        echo "   mkdir -p ~/.ssh"
        echo "   echo '$pub_key_content' >> ~/.ssh/authorized_keys"
        echo "   chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
        echo
        read -p "Appuyez sur Entrée une fois terminé..."
    fi
}

test_ssh_connection() {
    header
    log "Test de la connexion SSH..."
    
    # Test avec clé
    if [ -f "$SSH_KEY_PATH" ]; then
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o BatchMode=yes \
           "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" exit 2>/dev/null; then
            success "✅ Connexion SSH avec clé: RÉUSSIE"
            
            # Test commande
            local hostname=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" "hostname" 2>/dev/null)
            log "Hostname Pwnagotchi: $hostname"
            
            # Test répertoire handshakes
            local handshake_count=$(ssh -i "$SSH_KEY_PATH" "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" \
                "find $PWNAGOTCHI_HANDSHAKE_DIR -name '*.pcap*' 2>/dev/null | wc -l")
            log "Handshakes disponibles: $handshake_count"
            
            return 0
        else
            error "❌ Connexion SSH avec clé: ÉCHEC"
        fi
    fi
    
    # Test avec mot de passe
    if command -v sshpass >/dev/null 2>&1; then
        if sshpass -p "$PWNAGOTCHI_PASS" ssh -o ConnectTimeout=5 \
           "$PWNAGOTCHI_USER@$PWNAGOTCHI_IP" exit 2>/dev/null; then
            warn "⚠️  Connexion SSH avec mot de passe: RÉUSSIE (configuration clé recommandée)"
        else
            error "❌ Connexion SSH avec mot de passe: ÉCHEC"
        fi
    else
        warn "sshpass non disponible pour test mot de passe"
    fi
}

remove_ssh_keys() {
    header
    echo -e "${RED}⚠️  SUPPRESSION DES CLÉS SSH${NC}"
    echo
    echo "Cette action supprimera définitivement:"
    echo "  - Clé privée: $SSH_KEY_PATH"
    echo "  - Clé publique: ${SSH_KEY_PATH}.pub"
    echo
    
    read -p "Confirmer la suppression? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy] ]]; then
        rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
        success "Clés SSH supprimées"
    else
        log "Suppression annulée"
    fi
}

manual_ssh_config() {
    header
    echo -e "${BLUE}🔧 CONFIGURATION MANUELLE SSH${NC}"
    echo
    echo "Configuration actuelle:"
    echo "  IP Pwnagotchi: $PWNAGOTCHI_IP"
    echo "  Utilisateur: $PWNAGOTCHI_USER"
    echo "  Mot de passe: $PWNAGOTCHI_PASS"
    echo "  Clé SSH: $SSH_KEY_PATH"
    echo "  Répertoire distant: $PWNAGOTCHI_HANDSHAKE_DIR"
    echo
    
    echo "1) Modifier l'IP du Pwnagotchi"
    echo "2) Modifier l'utilisateur SSH"
    echo "3) Modifier le mot de passe"
    echo "4) Modifier le répertoire des handshakes"
    echo "5) Tester la configuration actuelle"
    echo "6) Retour"
    echo
    
    read -p "Votre choix [1-6]: " choice
    
    case $choice in
        1)
            read -p "Nouvelle IP [$PWNAGOTCHI_IP]: " new_ip
            if [ -n "$new_ip" ]; then
                sed -i "s/PWNAGOTCHI_IP=.*/PWNAGOTCHI_IP=\"$new_ip\"/" "$CONFIG_FILE"
                success "IP mise à jour: $new_ip"
            fi
            ;;
        2)
            read -p "Nouvel utilisateur [$PWNAGOTCHI_USER]: " new_user
            if [ -n "$new_user" ]; then
                sed -i "s/PWNAGOTCHI_USER=.*/PWNAGOTCHI_USER=\"$new_user\"/" "$CONFIG_FILE"
                success "Utilisateur mis à jour: $new_user"
            fi
            ;;
        3)
            read -s -p "Nouveau mot de passe: " new_pass
            echo
            if [ -n "$new_pass" ]; then
                sed -i "s/PWNAGOTCHI_PASS=.*/PWNAGOTCHI_PASS=\"$new_pass\"/" "$CONFIG_FILE"
                success "Mot de passe mis à jour"
            fi
            ;;
        4)
            read -p "Nouveau répertoire [$PWNAGOTCHI_HANDSHAKE_DIR]: " new_dir
            if [ -n "$new_dir" ]; then
                sed -i "s|PWNAGOTCHI_HANDSHAKE_DIR=.*|PWNAGOTCHI_HANDSHAKE_DIR=\"$new_dir\"|" "$CONFIG_FILE"
                success "Répertoire mis à jour: $new_dir"
            fi
            ;;
        5)
            test_ssh_connection
            return
            ;;
        6)
            return
            ;;
        *)
            warn "Option invalide"
            ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    manual_ssh_config
}
