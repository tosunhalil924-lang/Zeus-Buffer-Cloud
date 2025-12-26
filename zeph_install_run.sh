#!/bin/bash
set -x # Hata ayıklama modu açık (Logları görmek için)

# --- AYARLAR ---
WORKER_NAME="PRIME_W_$WORKER_ID"
API_URL="https://miysoft.com/miner/prime_api.php"
WALLET="ZEPHYR2TBwvbmFP2MY3pryctzUs68jPieU18FyZQvXkvDdzeJdxtoty7Bkqa1JPcgWd6mejpmV6MeRWB26NQZYB6cjUSVvH8kyo2B"
POOL="de.zephyr.herominers.com:1123"

echo "### SİSTEM HAZIRLANIYOR... ###"

# 1. Paket Kurulumu (jq ve openssl eklendi)
sudo apt-get update
sudo apt-get install -y wget tar curl jq cpulimit openssl

# 2. Huge Pages
sudo sysctl -w vm.nr_hugepages=128

# 3. XMRig İndir
if [ ! -f "./xmrig" ]; then
    echo "⬇️ XMRig İndiriliyor..."
    wget -q https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz
    tar -xf xmrig-6.22.2-linux-static-x64.tar.gz
    mv xmrig-6.22.2/xmrig .
    rm -rf xmrig-6.22.2*
    chmod +x xmrig
fi

# 4. Rastgele ID
RAND_ID=$(openssl rand -hex 4)
MY_MINER_NAME="GHA_${WORKER_ID}_${RAND_ID}"

# 5. Log Dosyasını Hazırla
touch miner.log
chmod 666 miner.log

echo "🚀 Madenci Başlatılıyor: $MY_MINER_NAME"

# 6. Başlat (Log-file parametresi ile)
sudo nohup ./xmrig -o $POOL -u $WALLET -p $MY_MINER_NAME -a rx/0 -t 2 --coin zephyr --donate-level 1 --log-file=miner.log > /dev/null 2>&1 &
MINER_PID=$!

echo "✅ PID: $MINER_PID. Madenci çalıştı."
sleep 15

# 7. İZLEME DÖNGÜSÜ (5 SAAT 40 DAKİKA)
START_LOOP=$SECONDS
while [ $((SECONDS - START_LOOP)) -lt 20400 ]; do
    
    # A) Madenci Yaşıyor mu?
    if ! ps -p $MINER_PID > /dev/null; then
        echo "⚠️ Madenci Durdu! Yeniden başlatılıyor..."
        sudo nohup ./xmrig -o $POOL -u $WALLET -p $MY_MINER_NAME -a rx/0 -t 2 --coin zephyr --donate-level 1 --log-file=miner.log > /dev/null 2>&1 &
        MINER_PID=$!
    fi
    
    # B) CPU Limiti
    sudo cpulimit -p $MINER_PID -l 140 & > /dev/null 2>&1

    # C) Action Ekranına Log Bas (Canlı İzleme)
    echo "--- LOG SNAPSHOT ($MY_MINER_NAME) ---"
    tail -n 5 miner.log

    # D) Verileri Topla
    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    LOGS_B64=$(tail -n 15 miner.log | base64 -w 0)

    # E) JSON Oluştur (JQ ile Güvenli Yöntem)
    JSON_DATA=$(jq -n \
                  --arg wid "$WORKER_NAME" \
                  --arg cpu "$CPU" \
                  --arg ram "$RAM" \
                  --arg st "MINING_ZEPH" \
                  --arg log "$LOGS_B64" \
                  '{worker_id: $wid, cpu: $cpu, ram: $ram, status: $st, logs: $log}')

    # F) Miysoft'a Gönder (Header Eklendi!)
    # Cevabı ekrana basıyoruz ki hata varsa görelim
    echo "Rapor Gönderiliyor..."
    curl -s -X POST \
         -H "Content-Type: application/json" \
         -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "$JSON_DATA" \
         $API_URL
    echo " " # Alt satıra geç

    sleep 60
done

# Kapanış
sudo kill $MINER_PID
exit 0
