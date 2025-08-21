# WiFiCyberTools v1.0

Suite complète d'outils de cybersécurité WiFi conçue pour l'analyse, la validation, la conversion et l'attaque de handshakes WiFi. Ce projet modulaire facilite les tests de pénétration et le travail avec des captures WiFi et Pwnagotchi.

---

## Fonctionnalités principales

- 🛠️ Installation automatique des outils et dépendances (hashcat, hcxtools, tshark, etc.)
- 🔑 Gestion complète des clés SSH pour interface avec Pwnagotchi
- 🔍 Vérification avancée des fichiers PCAP et validation des handshakes WPA/WPA2
- 🔄 Conversion fiable des captures en format hashcat 22000 (.hc22000)
- 🧹 Nettoyage intelligent des fichiers invalides, corrompus ou sans handshakes
- 📥 Synchronisation poussée avec Pwnagotchi (complète, incrémentale, sélective)
- 💥 Attaques optimisées avec Hashcat (dictionnaire, masque, hybride, reprise)
- 📊 Visualisation détaillée des résultats et statistiques globales
- 📚 Gestion des wordlists (fonctionnalités en cours de développement)

---

## Structure du projet
```
WiFiCyberTools/
├── cybertools.sh             # Script principal et menu interactif
├── install.sh                # Script d'installation automatique
├── README.md                 # Documentation
├── config/
│   ├── settings.conf         # Configuration générale (IPs, dossiers, paramètres)
│   └── wordlists.conf        # URLs de wordlists populaires
├── modules/
│   ├── installer.sh          # Installation des outils système
│   ├── ssh_manager.sh        # Gestion des clés SSH Pwnagotchi
│   ├── pcap_checker.sh       # Vérification des fichiers PCAP
│   ├── pwnagotchi_sync.sh    # Synchronisation avec Pwnagotchi
│   ├── handshake_validator.sh# Validation & conversion des handshakes
│   ├── pcap_cleaner.sh       # Nettoyage des captures invalides
│   ├── hashcat_runner.sh     # Gestion des attaques Hashcat
│   ├── wordlist_manager.sh   # Gestion des wordlists (en développement)
│   └── results_viewer.sh     # Visualisation des résultats des attaques
├── data/
│   ├── captures/             # Captures PCAP synchronisées
│   ├── converted/            # Fichiers convertis (.hc22000)
│   ├── wordlists/            # Wordlists (à compléter)
│   └── results/              # Résultats des attaques
└── logs/                     # Logs d'exécution et diagnostics
```
---

## Installation

Cloner le projet, lancer le script d’installation initiale puis installer les outils système :

git clone <url-du-dépôt> WiFiCyberTools  
cd WiFiCyberTools  
./install.sh  
sudo ./cybertools.sh --install

---

## Utilisation

Lancer l’interface interactive complète :

./cybertools.sh

Ou exécuter des commandes directes :

- Synchronisation Pwnagotchi :  
  `./cybertools.sh --sync`
  
- Attaque hashcat directe sur un fichier converti :  
  `./cybertools.sh --attack fichier.hc22000`
  
- Nettoyage automatique :  
  `./cybertools.sh --clean`

---

## Remarques importantes

- La gestion et optimisation des wordlists est actuellement en **cours de développement**.  
- Ce projet nécessite que `hcxpcapngtool`, `hashcat`, `tshark`, `rsync`, et `ssh` soient correctement installés.
- Le projet est conçu pour fonctionner avec un Pwnagotchi accessible en SSH avec clé configurée.
- Les modules sont modifiables et extensibles pour s’adapter à différents besoins spécifiques.

---

## Support & Contributions

Contributions, questions ou suggestions bienvenues via les issues du repository.  
Prise en charge des GPUs NVIDIA avec gestion de la température et optimisation.

---

WiFiCyberTools propose une architecture claire et évolutive pour toutes les phases du pentest WiFi : collecte, validation, conversion, attaque, et analyse des résultats.


---

☕️ Si ce projet vous est utile ou vous plaît, vous pouvez me soutenir ici : [buymeacoffee.com/rapatt](https://buymeacoffee.com/rapatt)

---

Restez connecté, restez sécurisé !
Created by Rapatt
