#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# netns-chaosbox - Deploy Script (V1.0 Version)
#
# Network Topology:
#
#   root namespace                     chaosbox namespace
#   -----------------                  ---------------------
#   veth0  <------------------------->  veth1
#   veth2 (netem)  <----------------->  veth3
#
#   Outbound traffic flow:
#      Client → APP(softvpn) → root → veth0 → chaosbox → veth3 → veth2 (delay/loss/etc) → ens4 → Internet
#
#   Inbound traffic flow:
#      Internet → ens4 → root routing → veth2 → veth3 → chaosbox → veth1 → veth0 → root → APP(softvpn) → Client
#
# This script:
#   - Creates namespaces & veth pairs
#   - Configures routing tables and policy routing
#   - Applies NAT (root + namespace)
#   - Adds traffic impairment via tc netem
#
# Designed for reproducible and deterministic network simulation.
###############################################################################

# Determine script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/chaosbox.conf"

# Placeholder marker used in chaosbox.conf
PLACEHOLDER="__REQUIRED_CHANGE_ME__"

# Utility: require a variable to be set and not be the placeholder
require_var() {
  local name="$1"
  local value="${!name:-}"

  if [ -z "${value}" ] || [ "${value}" = "${PLACEHOLDER}" ]; then
    echo "[chaosbox][ERROR] Required variable '${name}' is not properly set."
    echo "[chaosbox] Please edit '${CONFIG_FILE}' and set a valid value for '${name}'."
    exit 1
  fi
}

### === Load user config (mandatory) === ###
if [ -f "${CONFIG_FILE}" ]; then
  echo "[chaosbox] Loading user config from ${CONFIG_FILE}"
  # shellcheck disable=SC1090
  . "${CONFIG_FILE}"
else
  echo "[chaosbox][ERROR] Config file not found: ${CONFIG_FILE}"
  echo "[chaosbox] Please create and edit this file before running Chaosbox."
  exit 1
fi

### === Validate required variables (no defaults) === ###
require_var "WAN_DEV"
require_var "WAN_DEV_IP"
require_var "MGMT_NET1"
require_var "MGMT_NET2"

echo "[chaosbox] Effective configuration:"
echo "  WAN_DEV   = ${WAN_DEV}"
echo "  WAN_DEV_IP= ${WAN_DEV_IP}"
echo "  MGMT_NET1 = ${MGMT_NET1}"
echo "  MGMT_NET2 = ${MGMT_NET2}"

### === Default configuration , But it's adjustable. ======================= ###  
NS="chaosbox"
# veth pairs
VETH_ROOT_IN="veth0"
VETH_NS_IN="veth1"
VETH_ROOT_OUT="veth2"
VETH_NS_OUT="veth3"

# IP addressing
VETH_ROOT_IN_IP="10.0.0.1/30"
VETH_NS_IN_IP="10.0.0.2/30"

VETH_ROOT_OUT_IP="10.0.1.1/30"
VETH_NS_OUT_IP="10.0.1.2/30"

NET_IN="10.0.0.0/30"
NET_OUT="10.0.1.0/30"

# Routing table
RT_TABLE_ID=100
RT_TABLE_NAME="chaosbox"

# Traffic impairment (you can change this)
IMPAIR_DEV="${VETH_ROOT_OUT}"
IMPAIR_QDISC="netem delay 100ms"
### ======================================================================== ###

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

run() {
    echo "+ $*"
    eval "$@"
}

###############################################################################
# Start Deployment
###############################################################################

log "Starting netns-chaosbox deployment…"

if ! ip link show "${WAN_DEV}" >/dev/null 2>&1; then
    echo "ERROR: WAN interface '${WAN_DEV}' does not exist." >&2
    exit 1
fi

###############################################################################
# Create namespace
###############################################################################

if ip netns list | grep -q "^${NS}\b"; then
    log "Namespace ${NS} already exists (skipping)."
else
    log "Creating namespace ${NS}"
    run "ip netns add ${NS}"
fi

###############################################################################
# Create veth pairs
###############################################################################

if ! ip link show "${VETH_ROOT_IN}" >/dev/null 2>&1; then
    log "Creating veth pair ${VETH_ROOT_IN} <-> ${VETH_NS_IN}"
    run "ip link add ${VETH_ROOT_IN} type veth peer name ${VETH_NS_IN}"
    run "ip link set ${VETH_NS_IN} netns ${NS}"
else
    log "${VETH_ROOT_IN} already exists (skipping)."
fi

if ! ip link show "${VETH_ROOT_OUT}" >/dev/null 2>&1; then
    log "Creating veth pair ${VETH_ROOT_OUT} <-> ${VETH_NS_OUT}"
    run "ip link add ${VETH_ROOT_OUT} type veth peer name ${VETH_NS_OUT}"
    run "ip link set ${VETH_NS_OUT} netns ${NS}"
else
    log "${VETH_ROOT_OUT} already exists (skipping)."
fi

###############################################################################
# Configure veth in root namespace
###############################################################################

log "Configuring root veth interfaces"
run "ip addr flush dev ${VETH_ROOT_IN} || true"
run "ip addr flush dev ${VETH_ROOT_OUT} || true"

run "ip addr add ${VETH_ROOT_IN_IP} dev ${VETH_ROOT_IN}"
run "ip addr add ${VETH_ROOT_OUT_IP} dev ${VETH_ROOT_OUT}"

run "ip link set ${VETH_ROOT_IN} up"
run "ip link set ${VETH_ROOT_OUT} up"

###############################################################################
# Configure namespace interfaces
###############################################################################

log "Configuring interfaces inside namespace ${NS}"
run "ip netns exec ${NS} ip link set lo up"

run "ip netns exec ${NS} ip addr flush dev ${VETH_NS_IN} || true"
run "ip netns exec ${NS} ip addr flush dev ${VETH_NS_OUT} || true"

run "ip netns exec ${NS} ip addr add ${VETH_NS_IN_IP} dev ${VETH_NS_IN}"
run "ip netns exec ${NS} ip addr add ${VETH_NS_OUT_IP} dev ${VETH_NS_OUT}"

run "ip netns exec ${NS} ip link set ${VETH_NS_IN} up"
run "ip netns exec ${NS} ip link set ${VETH_NS_OUT} up"

log "Setting namespace default route via ${VETH_NS_OUT} → ${VETH_ROOT_OUT_IP%%/*}"
run "ip netns exec ${NS} ip route replace default via ${VETH_ROOT_OUT_IP%%/*} dev ${VETH_NS_OUT}"

log "Setting namespace host route via ${VETH_NS_OUT} → ${VETH_ROOT_IN_IP%%/*}"
run "ip netns exec ${NS} ip route replace ${WAN_DEV_IP%%/*} via ${VETH_ROOT_IN_IP%%/*} dev ${VETH_NS_IN}"

###############################################################################
# Enable IP forwarding
###############################################################################

log "Enabling IPv4 forwarding"
run "sysctl -w net.ipv4.ip_forward=1"
run "ip netns exec ${NS} sysctl -w net.ipv4.ip_forward=1"

###############################################################################
# Configure root routing
###############################################################################

log "Setting root routing for veth networks"
run "ip route replace ${NET_IN} dev ${VETH_ROOT_IN}"
run "ip route replace ${NET_OUT} dev ${VETH_ROOT_OUT}"

###############################################################################
# Route table registration
###############################################################################

if ! grep -qE "^${RT_TABLE_ID}[[:space:]]+${RT_TABLE_NAME}\$" /etc/iproute2/rt_tables; then
    log "Registering route table ${RT_TABLE_ID} → ${RT_TABLE_NAME}"
    echo "${RT_TABLE_ID} ${RT_TABLE_NAME}" | sudo tee -a /etc/iproute2/rt_tables >/dev/null
fi

log "Adding default route to table 'chaosbox'"
run "ip route replace default via ${VETH_NS_IN_IP%%/*} dev ${VETH_ROOT_IN} table ${RT_TABLE_NAME}"

###############################################################################
# Policy routing - core logic (your final model)
###############################################################################

log "Installing policy routing rules"

run "ip rule add to ${MGMT_NET1} lookup main pref 100 || true"
run "ip rule add to ${MGMT_NET2} lookup main pref 110 || true"
run "ip rule add to ${NET_OUT} lookup main pref 140 || true"  
run "ip rule add from ${VETH_NS_OUT_IP} lookup main pref 150 || true"  
run "ip rule add lookup ${RT_TABLE_NAME} pref 200 || true"

###############################################################################
# iptables configuration
###############################################################################

log "Flushing iptables (WARNING: this removes all rules)"
run "iptables -F"
run "iptables -t nat -F"
run "iptables -t mangle -F"
run "iptables -t raw -F"

log "Applying MASQUERADE inside namespace ${NS}"
run "ip netns exec ${NS} iptables -t nat -A POSTROUTING -o ${VETH_NS_OUT} -j MASQUERADE"

log "Applying MASQUERADE on root"
run "iptables -t nat -A POSTROUTING -o ${WAN_DEV} -j MASQUERADE"

log "Reduce docker's impact"
run "iptables -I FORWARD -i ${VETH_ROOT_OUT} -o ${WAN_DEV} -j ACCEPT"
run "iptables -I FORWARD -i ${WAN_DEV} -o ${VETH_ROOT_OUT} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"

###############################################################################
# Traffic impairment
###############################################################################

log "Applying network impairment on ${IMPAIR_DEV}: ${IMPAIR_QDISC}"
run "tc qdisc del dev ${IMPAIR_DEV} root 2>/dev/null || true"
run "tc qdisc add dev ${IMPAIR_DEV} root ${IMPAIR_QDISC}"

log "Deployment completed successfully."