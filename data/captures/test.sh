#!/bin/bash
# check_all_handshakes.sh
# Usage: ./check_all_handshakes.sh /chemin/vers/ton/dossier

if [ $# -lt 1 ]; then
    echo "Usage: $0 <dossier_avec_pcaps>"
    exit 1
fi

DIR="$1"

# Vérifier que le dossier existe
if [ ! -d "$DIR" ]; then
    echo "Erreur: $DIR n'est pas un dossier valide"
    exit 1
fi

for FILE in "$DIR"/*.pcap "$DIR"/*.pcapng; do
    # Vérifie si le fichier existe (évite le cas "aucun fichier trouvé")
    [ -e "$FILE" ] || continue
    
    BASENAME=$(basename "$FILE")
    OUTPUT="${DIR}/${BASENAME%.*}.hc22000"

    echo "[*] Traitement de $BASENAME ..."
    hcxpcapngtool -o "$OUTPUT" "$FILE" > /dev/null 2>&1

    if [ -s "$OUTPUT" ]; then
        echo "   [+] Handshake trouvé → $OUTPUT"
    else
        echo "   [-] Aucun handshake valide"
        rm -f "$OUTPUT"
    fi
done
