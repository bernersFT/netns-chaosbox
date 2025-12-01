#!/bin/sh
set -e

VPN_DIR="/usr/local/vpnserver"
VPN_CMD="${VPN_DIR}/vpncmd"
VPN_SERVER="${VPN_DIR}/vpnserver"
INIT_FLAG="${VPN_DIR}/.chaosbox_inited"

SERVER_PASS="${VPN_SERVER_PASSWORD:-chaosbox}"
HUB_NAME="${VPN_HUB_NAME:-chaosbox}"
HUB_PASS="${VPN_HUB_PASSWORD:-${HUB_NAME}}"
USER_NAME="${VPN_USER_NAME:-chaosbox}"
USER_PASS="${VPN_USER_PASSWORD:-${USER_NAME}}"
IPSEC_PSK="${VPN_IPSEC_PSK:-${HUB_NAME}}"
ENABLE_IPSEC="${VPN_ENABLE_IPSEC:-1}"  

echo "[entrypoint] SERVER_PASS=${SERVER_PASS}, HUB_NAME=${HUB_NAME}, USER_NAME=${USER_NAME}, ENABLE_IPSEC=${ENABLE_IPSEC}"

wait_for_server() {
  echo "[entrypoint] waiting for vpnserver to be ready..."
  i=1
  while [ "$i" -le 10 ]; do
    if "${VPN_CMD}" localhost /SERVER /CMD ServerStatusGet >/dev/null 2>&1; then
      echo "[entrypoint] vpnserver is ready (try ${i})"
      return 0
    fi
    i=$((i+1))
    sleep 2
  done
  echo "[entrypoint] ERROR: vpnserver not ready after several attempts."
  return 1
}

if [ ! -f "$INIT_FLAG" ]; then
  echo "[entrypoint] First start, initializing SoftEther..."

  "${VPN_SERVER}" start
  sleep 3

  wait_for_server

  echo "[entrypoint] setting server admin password..."
  "${VPN_CMD}" localhost /SERVER \
    /CMD ServerPasswordSet "${SERVER_PASS}"

  echo "[entrypoint] creating hub ${HUB_NAME}..."
  "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" \
    /CMD HubCreate "${HUB_NAME}" /PASSWORD:"${HUB_PASS}"

  echo "[entrypoint] switching to hub ${HUB_NAME} and set Online..."
  "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" /HUB:"${HUB_NAME}" \
    /CMD Online

  echo "[entrypoint] creating user ${USER_NAME}..."
  "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" /HUB:"${HUB_NAME}" \
    /CMD UserCreate "${USER_NAME}" /GROUP:none /REALNAME:none /NOTE:none

  echo "[entrypoint] setting password for user ${USER_NAME}..."
  "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" /HUB:"${HUB_NAME}" \
    /CMD UserPasswordSet "${USER_NAME}" /PASSWORD:"${USER_PASS}"

  echo "[entrypoint] enabling SecureNAT..."
  "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" /HUB:"${HUB_NAME}" \
    /CMD SecureNatEnable

  echo "[entrypoint] deleting default hub if exists..."
  "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" \
    /CMD HubDelete default || echo "[entrypoint] default hub not found, ignore"

  if [ "$ENABLE_IPSEC" = "1" ]; then
    echo "[entrypoint] enabling IPsec/L2TP via script (PSK=${IPSEC_PSK}, HUB=${HUB_NAME})..."

    IPSEC_SCRIPT="/tmp/ipsec_enable.txt"
    cat > "$IPSEC_SCRIPT" <<EOF
IPsecEnable
yes
yes
yes
${IPSEC_PSK}
${HUB_NAME}
EOF

    set +e
    "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}" /IN:"${IPSEC_SCRIPT}"
    ipsec_rc=$?
    set -e
    rm -f "$IPSEC_SCRIPT"

    if [ "$ipsec_rc" -ne 0 ]; then
      echo "[entrypoint] WARNING: IPsecEnable via script failed with exit code ${ipsec_rc}" >&2
    else
      echo "[entrypoint] IPsecEnable via script succeeded (exit=${ipsec_rc})."
    fi
  else
    echo "[entrypoint] IPsec auto config disabled (VPN_ENABLE_IPSEC=${ENABLE_IPSEC})"
  fi

  touch "$INIT_FLAG"
  echo "[entrypoint] initialization done."

  echo "[entrypoint] stopping temporary vpnserver daemon..."
  "${VPN_SERVER}" stop || true
  sleep 2
fi

echo "[entrypoint] starting vpnserver in foreground: execsvc ..."
exec "${VPN_SERVER}" execsvc
