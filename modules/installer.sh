#!/bin/bash

# ==============================================================================
# Module d'installation WiFiCyberTools
# ==============================================================================

installer_menu() {
    header
    echo -e "${BLUE}🛠️  INSTALLATION ET CONFIGURATION${NC}"
    echo
    echo "1) Installation complète (requirements + outils)"
    echo "2) Installation des pilotes GPU"
    echo "3) Configuration Hashcat"
    echo "4) Test de l'installation"
    echo "5) Réparation de l'installation"
    echo "6) Retour au menu principal"
    echo
    
    read -p "Votre choix [1-6]: " choice
    
    case $choice in
        1) install_requirements ;;
        2) install_gpu_drivers ;;
        3) configure_hashcat ;;
        4) test_installation ;;
        5) repair_installation ;;
        6) return ;;
        *) warn "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    installer_menu
}

install_requirements() {
    header
    log "Installation des requirements..."
    
    if [ "$EUID" -ne 0 ]; then
        error "Installation nécessite les droits root (sudo)"
        return 1
    fi
    
    # Mise à jour système
    log "Mise à jour du système..."
    apt-get update -qq
    
    # Packages essentiels
    log "Installation des packages essentiels..."
    apt-get install -y \
        curl wget git \
        build-essential gcc make \
        python3 python3-pip \
        openssh-client rsync sshpass \
        wireshark-common tshark \
        aircrack-ng \
        libcurl4-openssl-dev libssl-dev zlib1g-dev \
        opencl-headers ocl-icd-opencl-dev \
        mesa-opencl-icd intel-opencl-icd
    
    # Installation hcxtools
    install_hcxtools
    
    # Installation Hashcat
    install_hashcat
    
    # Création de la structure
    create_directory_structure
    
    success "Installation des requirements terminée"
}

install_hcxtools() {
    log "Installation hcxtools..."
    
    cd /tmp
    rm -rf hcxtools
    git clone --depth 1 https://github.com/ZerBea/hcxtools.git
    cd hcxtools
    make clean && make -j$(nproc)
    make install PREFIX=/usr/local
    
    success "hcxtools installé"
}

install_hashcat() {
    log "Installation Hashcat depuis les sources..."
    
    cd /tmp
    rm -rf hashcat
    git clone --depth 1 https://github.com/hashcat/hashcat.git
    cd hashcat
    make clean && make -j$(nproc)
    make install PREFIX=/opt/hashcat
    
    # Lien symbolique
    ln -sf /opt/hashcat/bin/hashcat /usr/local/bin/hashcat
    
    success "Hashcat installé"
}

install_gpu_drivers() {
    header
    log "Installation des pilotes GPU..."
    
    # Détection GPU NVIDIA
    if lspci | grep -i nvidia >/dev/null; then
        log "GPU NVIDIA détecté, installation des pilotes..."
        
        # Nettoyage
        apt-get remove --purge -y 'nvidia-*' 'libnvidia-*' || true
        apt-get autoremove -y
        
        # Installation driver récent
        add-apt-repository -y ppa:graphics-drivers/ppa
        apt-get update -qq
        
        LATEST_DRIVER=$(apt-cache search 'nvidia-driver-[0-9]' | sort -V | tail -1 | awk '{print $1}')
        apt-get install -y "$LATEST_DRIVER"
        
        # CUDA Toolkit
        install_cuda_toolkit
        
        success "Pilotes NVIDIA installés"
    else
        warn "Aucun GPU NVIDIA détecté"
    fi
}

install_cuda_toolkit() {
    log "Installation CUDA Toolkit..."
    
    # Méthode propre avec APT
    local ubuntu_version=$(lsb_release -rs | tr -d '.')
    local keyring=/usr/share/keyrings/cuda-archive-keyring.gpg
    
    if [ ! -f "$keyring" ]; then
        wget -O- "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${ubuntu_version}/x86_64/3bf863cc.pub" | \
            gpg --dearmor > "$keyring"
        echo "deb [signed-by=$keyring] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${ubuntu_version}/x86_64/ /" > \
            /etc/apt/sources.list.d/cuda-ubuntu.list
        apt-get update -qq
    fi
    
    apt-get install -y cuda-toolkit
}

configure_hashcat() {
    header
    log "Configuration optimisée de Hashcat..."
    
    # Configuration globale
    mkdir -p /etc/hashcat
    cat > /etc/hashcat/hashcat.conf << EOF
# Configuration optimisée WiFiCyberTools
workload_profile = $HASHCAT_WORKLOAD
kernel_accel = 0
kernel_loops = 0
gpu_temp_abort = $GPU_TEMP_LIMIT
gpu_temp_retain = $((GPU_TEMP_LIMIT - 10))
EOF
    
    # Configuration NVIDIA timeout
    if command -v nvidia-smi >/dev/null 2>&1; then
        mkdir -p /usr/share/X11/xorg.conf.d
        cat > /usr/share/X11/xorg.conf.d/20-nvidia.conf << EOF
Section "Device"
    Identifier     "NVIDIA GPU"
    Driver         "nvidia"
    Option         "Interactive" "False"
    Option         "AllowNonGLXOverlay" "false"
EndSection
EOF
        log "Configuration NVIDIA timeout appliquée"
    fi
    
    success "Configuration Hashcat terminée"
}

create_directory_structure() {
    log "Création de la structure de répertoires..."
    
    local dirs=(
        "$DATA_DIR/captures"
        "$DATA_DIR/converted"
        "$DATA_DIR/wordlists"
        "$DATA_DIR/results"
        "$LOG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "Créé: $dir"
    done
    
    # Permissions
    chmod 755 "$SCRIPT_DIR/modules"/*.sh
    
    success "Structure créée"
}

test_installation() {
    header
    log "Test de l'installation..."
    
    local tests_passed=0
    local tests_total=0
    
    # Test des outils
    local tools=("hashcat" "hcxpcapngtool" "aircrack-ng" "tshark" "ssh")
    for tool in "${tools[@]}"; do
        tests_total=$((tests_total + 1))
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✅ $tool: OK"
            tests_passed=$((tests_passed + 1))
        else
            echo "  ❌ $tool: MANQUANT"
        fi
    done
    
    # Test Hashcat devices
    tests_total=$((tests_total + 1))
    if timeout 15 hashcat -I >/dev/null 2>&1; then
        echo "  ✅ Hashcat devices: OK"
        tests_passed=$((tests_passed + 1))
    else
        echo "  ❌ Hashcat devices: ÉCHEC"
    fi
    
    # Test benchmark
    tests_total=$((tests_total + 1))
    if timeout 30 hashcat -b -m 0 --quiet >/dev/null 2>&1; then
        echo "  ✅ Hashcat benchmark: OK"
        tests_passed=$((tests_passed + 1))
    else
        echo "  ❌ Hashcat benchmark: ÉCHEC"
    fi
    
    echo
    if [ "$tests_passed" -eq "$tests_total" ]; then
        success "Installation complète: $tests_passed/$tests_total tests réussis"
    else
        warn "Installation incomplète: $tests_passed/$tests_total tests réussis"
    fi
}

repair_installation() {
    header
    log "Réparation de l'installation..."
    
    # Réinstallation des outils manquants
    if ! command -v hashcat >/dev/null 2>&1; then
        install_hashcat
    fi
    
    if ! command -v hcxpcapngtool >/dev/null 2>&1; then
        install_hcxtools
    fi
    
    # Recréation des répertoires
    create_directory_structure
    
    # Test final
    test_installation
}
