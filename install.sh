#!/bin/bash
set -eo pipefail
shopt -s nullglob

if [ "$EUID" -ne 0 ]
then echo "Please run as root"
    exit
fi

if ! command -v qrencode &> /dev/null; then    
    echo "qrencode is not installed. Installing..."    
    apt install qrencode
fi

if ! command -v xray &> /dev/null; then    
    echo "Xray is not installed. Installing..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta
else
    echo "Xray is already installed."
fi


if [ ! -f "config.json" ]; then  
    cp "config.dist.json" "config.json"    
fi

if [ ! -f "default.json" ]; then  
    cp "default.dist.json" "default.json"    
fi

# Extract the desired variables using jq
name=$(jq -r '.name' default.json)
email=$(jq -r '.email' default.json)
port=$(jq -r '.port' default.json)
sni=$(jq -r '.sni' default.json)
path=$(jq -r '.path' default.json)
json=$(cat config.json)

keys=$(xray x25519)
pk=$(echo "$keys" | awk '/Private key:/ {print $3}')
pub=$(echo "$keys" | awk '/Public key:/ {print $3}')
serverIp=$(curl -s ipv4.wtfismyip.com/text)
uuid=$(xray uuid)
shortId=$(openssl rand -hex 8)

url="vless://$uuid@$serverIp:$port?type=http&security=reality&encryption=none&pbk=$pub&fp=chrome&path=$path&sni=$sni&sid=$shortId#$name"

newJson=$(echo "$json" | jq \
    --arg pk "$pk" \
    --arg uuid "$uuid" \
    --arg port "$port" \
    --arg sni "$sni" \
    --arg path "$path" \
    --arg email "$email" \
    '.inbounds[0].port= '"$(expr "$port")"' |
     .inbounds[0].settings.clients[0].email = $email |
     .inbounds[0].settings.clients[0].id = $uuid |
     .inbounds[0].streamSettings.realitySettings.dest = $sni + ":443" |
     .inbounds[0].streamSettings.realitySettings.serverNames += ["'$sni'", "www.'$sni'"] |
     .inbounds[0].streamSettings.realitySettings.privateKey = $pk |
     .inbounds[0].streamSettings.realitySettings.shortIds += ["'$shortId'"]')
     
echo "$newJson" | sudo tee /usr/local/etc/xray/config.json >/dev/null

echo ""
echo "$url"
echo ""

qrencode -s 120 -t ANSIUTF8 "$url"
qrencode -s 50 -o qr.png "$url"

sudo systemctl restart xray
