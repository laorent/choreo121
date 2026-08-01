#!/usr/bin/env bash

# 设置各变量
WSPATH=${WSPATH:-'argo'}
UUID=${UUID:-'de04add9-5c68-8bab-950c-08cd5320df18'}
WEB_USERNAME=${WEB_USERNAME:-'admin'}
WEB_PASSWORD=${WEB_PASSWORD:-'password'}

check_argo() {
  ! nc -vzw3 198.41.192.77 7844 && echo -e '********************\nError: Argo 不可用\n********************' && exit 1 || echo -e '********************\nArgo 可用\n********************'
}

generate_config() {
  cat > /tmp/config.json << EOF
{
    "log":{
        "access":"/dev/null",
        "error":"/dev/null",
        "loglevel":"none"
    },
    "inbounds":[
        {
            "port":8080,
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "flow":"xtls-rprx-vision"
                    }
                ],
                "decryption":"none",
                "fallbacks":[
                    {
                        "dest":3001
                    },
                    {
                        "path":"/${WSPATH}-vless",
                        "dest":3002
                    }
                ]
            },
            "streamSettings":{
                "network":"tcp"
            }
        },
        {
            "port":3001,
            "listen":"127.0.0.1",
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}"
                    }
                ],
                "decryption":"none"
            },
            "streamSettings":{
                "network":"ws",
                "security":"none"
            }
        },
        {
            "port":3002,
            "listen":"127.0.0.1",
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "level":0
                    }
                ],
                "decryption":"none"
            },
            "streamSettings":{
                "network":"ws",
                "security":"none",
                "wsSettings":{
                    "path":"/${WSPATH}-vless"
                }
            },
            "sniffing":{
                "enabled":true,
                "destOverride":[
                    "http",
                    "tls"
                ],
                "metadataOnly":false
            }
        }
    ],
    "dns":{
        "servers":[
            "https+local://8.8.8.8/dns-query"
        ]
    },
    "outbounds":[
        {
            "protocol":"freedom"
        },
        {
            "tag":"WARP",
            "protocol":"wireguard",
            "settings":{
                "secretKey":"cKE7LmCF61IhqqABGhvJ44jWXp8fKymcMAEVAzbDF2k=",
                "address":[
                    "172.16.0.2/32",
                    "fd01:5ca1:ab1e:823e:e094:eb1c:ff87:1fab/128"
                ],
                "peers":[
                    {
                        "publicKey":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                        "endpoint":"162.159.193.10:2408"
                    }
                ]
            }
        }
    ],
    "routing":{
        "domainStrategy":"AsIs",
        "rules":[
            {
                "type":"field",
                "domain":[
                    "domain:openai.com",
                    "domain:ai.com"
                ],
                "outboundTag":"WARP"
            }
        ]
    }
}
EOF
}

generate_argo() {
  cat > /tmp/argo.sh << ABC
#!/usr/bin/env bash

argo_type() {
  [[ \$ARGO_AUTH =~ TunnelSecret ]] && echo \$ARGO_AUTH > /tmp/tunnel.json && cat > /tmp/tunnel.yml << EOF
tunnel: \$(cut -d\" -f12 <<< \$ARGO_AUTH)
credentials-file: /tmp/tunnel.json
protocol: http2

ingress:
  - hostname: \$ARGO_DOMAIN
    service: http://localhost:8080
EOF

  [ -n "\${SSH_DOMAIN}" ] && cat >> /tmp/tunnel.yml << EOF
  - hostname: \$SSH_DOMAIN
    service: http://localhost:2222
EOF

  cat >> /tmp/tunnel.yml << EOF
  - service: http_status:404
EOF
}

export_list() {
  cat > /tmp/list << EOF
*******************************************
V2-rayN:
----------------------------
vless://${UUID}@icook.hk:443?encryption=none&security=tls&sni=\${ARGO_DOMAIN}&type=ws&host=\${ARGO_DOMAIN}&path=%2F${WSPATH}-vless?ed=2048#Argo-Vless
*******************************************
小火箭:
----------------------------
vless://${UUID}@icook.hk:443?encryption=none&security=tls&type=ws&host=\${ARGO_DOMAIN}&path=/${WSPATH}-vless?ed=2048&sni=\${ARGO_DOMAIN}#Argo-Vless
*******************************************
Clash:
----------------------------
- {name: Argo-Vless, type: vless, server: icook.hk, port: 443, uuid: ${UUID}, tls: true, servername: \${ARGO_DOMAIN}, skip-cert-verify: false, network: ws, ws-opts: {path: /${WSPATH}-vless?ed=2048, headers: {Host: \${ARGO_DOMAIN}}}}
*******************************************
EOF
  cat /tmp/list
}

argo_type
export_list
ABC
}

generate_pm2_file() {
  [[ $ARGO_AUTH =~ TunnelSecret ]] && ARGO_ARGS="tunnel --edge-ip-version auto --config /tmp/tunnel.yml run"
  [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]] && ARGO_ARGS="tunnel --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH}"

  cat > /tmp/ecosystem.config.js << EOF
module.exports = {
  "apps":[
      {
          "name":"web",
          "script":"/home/choreouser/web.js run -c /tmp/config.json"
      },
      {
          name: 'argo',
          script: 'cloudflared',
          args: "${ARGO_ARGS}",
          out_file: "/dev/null",
          error_file: "/dev/null"
      },
      {
          name: 'ttyd',
          script: '/home/choreouser/ttyd',
          args: "-c ${WEB_USERNAME}:${WEB_PASSWORD} -p 2222 bash",
          out_file: "/dev/null",
          error_file: "/dev/null"
      }
  ]
}
EOF
}

check_argo
generate_config
generate_argo
generate_pm2_file

[ -e /tmp/argo.sh ] && bash /tmp/argo.sh
[ -e /tmp/ecosystem.config.js ] && pm2 start /tmp/ecosystem.config.js
