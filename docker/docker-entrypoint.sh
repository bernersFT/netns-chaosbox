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

  # Configure IPsec/L2TP by simulating interactive input via stdin
  if [ "$ENABLE_IPSEC" = "1" ]; then
    echo "[entrypoint] enabling IPsec/L2TP via interactive stdin (PSK=${IPSEC_PSK}, HUB=${HUB_NAME})..."

    set +e
    # We run vpncmd in interactive server-admin mode and feed the exact
    # sequence of keys you would type by hand:
    #   1) IPsecEnable
    #   2) yes (L2TP over IPsec)
    #   3) yes (Raw L2TP)
    #   4) yes (EtherIP / L2TPv3 over IPsec)
    #   5) <PSK>
    #   6) <Default Hub>
    printf 'IPsecEnable\nyes\nyes\nyes\n%s\n%s\n' "${IPSEC_PSK}" "${HUB_NAME}" \
      | "${VPN_CMD}" localhost /SERVER /PASSWORD:"${SERVER_PASS}"
    ipsec_rc=$?
    set -e

    if [ "$ipsec_rc" -ne 0 ]; then
      echo "[entrypoint] WARNING: IPsecEnable via stdin failed with exit code ${ipsec_rc}" >&2
    else
      echo "[entrypoint] IPsecEnable via stdin succeeded (exit=${ipsec_rc})."
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

### ---------------------------------------------------------------
### Patch vpn_server.config (SecureNAT RAW/KERNEL mode disable)
### ---------------------------------------------------------------
CONFIG_FILE="${VPN_DIR}/vpn_server.config"

if [ -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] Patching vpn_server.config (DisableIpRawModeSecureNAT, DisableKernelModeSecureNAT) ..."

    sed -i 's/^\([[:space:]]*bool DisableIpRawModeSecureNAT\) .*/\1 true/' "$CONFIG_FILE"
    sed -i 's/^\([[:space:]]*bool DisableKernelModeSecureNAT\) .*/\1 true/' "$CONFIG_FILE"

    echo "[entrypoint] Patch completed. Current values:"
    grep DisableIpRawModeSecureNAT "$CONFIG_FILE" || true
    grep DisableKernelModeSecureNAT "$CONFIG_FILE" || true
else
    echo "[entrypoint] WARNING: vpn_server.config not found, skipping patch."
fi

echo "[entrypoint] starting vpnserver in foreground: execsvc ..."
exec "${VPN_SERVER}" execsvc