#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# netns-chaosbox - Rollback Script (V2.0)
#
# This script reverts the changes made by run_chaosbox.sh:
#   - Removes tc qdisc on impairment interface
#   - Deletes policy routing rules
#   - Flushes the custom route table (chaosbox)
#   - Deletes the namespace and its veth peers
#   - Cleans up iptables NAT rules and resets FORWARD policy
#   - Optionally removes custom table entry in /etc/iproute2/rt_tables
#
# All critical parameters are read from:
#   - chaosbox.conf          (WAN-related)
#   - chaosbox/latest/run_chaosbox.sh (namespace, veth, rt-table, nets)
###############################################################################

#############################################
# 0. Common helpers
#############################################

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [rollback] $*"
}

run() {
    echo "+ $*"
    eval "$@"
}


get_var() {
    local file="$1"
    local key="$2"
    local default="${3:-}"

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi


    local line
    line=$(grep -E "^${key}=" "$file" 2>/dev/null | head -n1 || true)
    if [[ -z "$line" ]]; then
        echo "$default"
        return
    fi

    local value="${line#*=}"

    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"

    echo "$value"
}

log "Starting netns-chaosbox rollback…"

#############################################
# 1. Locate project root / config / run_chaosbox.sh
#############################################


SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
CHAOSBOX_DIR="$(dirname "$SCRIPT_DIR")"          # .../chaosbox
PROJECT_ROOT="$(dirname "$CHAOSBOX_DIR")"       

CHAOSBOX_CONF="${PROJECT_ROOT}/chaosbox.conf"
RUN_CHAOSBOX="${CHAOSBOX_DIR}/latest/run_chaosbox.sh"

log "SCRIPT_DIR    = ${SCRIPT_DIR}"
log "CHAOSBOX_DIR  = ${CHAOSBOX_DIR}"
log "PROJECT_ROOT  = ${PROJECT_ROOT}"
log "CHAOSBOX_CONF = ${CHAOSBOX_CONF}"
log "RUN_CHAOSBOX  = ${RUN_CHAOSBOX}"

if [[ ! -f "${CHAOSBOX_CONF}" ]]; then
    log "ERROR: chaosbox.conf not found at: ${CHAOSBOX_CONF}"
    exit 1
fi

if [[ ! -f "${RUN_CHAOSBOX}" ]]; then
    log "ERROR: run_chaosbox.sh not found at: ${RUN_CHAOSBOX}"
    exit 1
fi

#############################################
# 2. Load parameters from chaosbox.conf / run_chaosbox.sh
#############################################

# WAN-related from chaosbox.conf (MUST be set by user)
WAN_DEV="$(get_var "${CHAOSBOX_CONF}" "WAN_DEV")"
WAN_DEV_IP="$(get_var "${CHAOSBOX_CONF}" "WAN_DEV_IP")"

if [[ -z "${WAN_DEV}" || -z "${WAN_DEV_IP}" ]]; then
    log "ERROR: WAN_DEV or WAN_DEV_IP is empty in chaosbox.conf"
    exit 1
fi

# NS / veth / routes / table from run_chaosbox.sh
NS="$(get_var "${RUN_CHAOSBOX}" "NS" "chaosbox")"
VETH_ROOT_IN="$(get_var "${RUN_CHAOSBOX}" "VETH_ROOT_IN" "veth0")"
VETH_NS_IN="$(get_var "${RUN_CHAOSBOX}" "VETH_NS_IN" "veth1")"
VETH_ROOT_OUT="$(get_var "${RUN_CHAOSBOX}" "VETH_ROOT_OUT" "veth2")"
VETH_NS_OUT="$(get_var "${RUN_CHAOSBOX}" "VETH_NS_OUT" "veth3")"

RT_TABLE_ID="$(get_var "${RUN_CHAOSBOX}" "RT_TABLE_ID" "100")"
RT_TABLE_NAME="$(get_var "${RUN_CHAOSBOX}" "RT_TABLE_NAME" "chaosbox")"

NET_IN="$(get_var "${RUN_CHAOSBOX}" "NET_IN" "10.0.0.0/30")"
NET_OUT="$(get_var "${RUN_CHAOSBOX}" "NET_OUT" "10.0.1.0/30")"

log "Loaded parameters:"
log "  NS            = ${NS}"
log "  WAN_DEV       = ${WAN_DEV}"
log "  WAN_DEV_IP    = ${WAN_DEV_IP}"
log "  VETH_ROOT_IN  = ${VETH_ROOT_IN}"
log "  VETH_NS_IN    = ${VETH_NS_IN}"
log "  VETH_ROOT_OUT = ${VETH_ROOT_OUT}"
log "  VETH_NS_OUT   = ${VETH_NS_OUT}"
log "  RT_TABLE_ID   = ${RT_TABLE_ID}"
log "  RT_TABLE_NAME = ${RT_TABLE_NAME}"
log "  NET_IN        = ${NET_IN}"
log "  NET_OUT       = ${NET_OUT}"
log "------------------------------------------------------------"

###############################################################################
# 3. Remove tc qdisc from impairment interface (VETH_ROOT_OUT)
###############################################################################

if ip link show "${VETH_ROOT_OUT}" >/dev/null 2>&1; then
    log "Removing qdisc from ${VETH_ROOT_OUT} (if present)"
    run "tc qdisc del dev ${VETH_ROOT_OUT} root 2>/dev/null || true"
else
    log "Interface ${VETH_ROOT_OUT} not found, skipping qdisc removal."
fi

###############################################################################
# 4. Remove policy routing rules
###############################################################################

log "Removing policy routing rules (if present)"

for pref in 100 110 120 130 140 150 160 170 180 190 200; do
    run "ip rule del pref ${pref} 2>/dev/null || true"
done

###############################################################################
# 5. Flush custom route table
###############################################################################

log "Flushing routes in table '${RT_TABLE_NAME}'"
run "ip route flush table ${RT_TABLE_NAME} 2>/dev/null || true"

log "Removing direct routes for ${NET_IN} and ${NET_OUT} from main table"
run "ip route del ${NET_IN} dev ${VETH_ROOT_IN} 2>/dev/null || true"
run "ip route del ${NET_OUT} dev ${VETH_ROOT_OUT} 2>/dev/null || true"

###############################################################################
# 6. Clean up iptables MASQUERADE rules
###############################################################################

log "Removing MASQUERADE rules on root ns (matching -o ${WAN_DEV})"

if command -v iptables >/dev/null 2>&1; then
    while iptables -t nat -S POSTROUTING 2>/dev/null | grep -q "MASQUERADE" | grep -q "\-o ${WAN_DEV}"; do
        RULE=$(iptables -t nat -S POSTROUTING | grep "MASQUERADE" | grep "\-o ${WAN_DEV}" | head -n1)
        RULE=${RULE/-A /-D }
        run "iptables -t nat ${RULE}"
    done
else
    log "WARNING: iptables not found, skipping root ns NAT cleanup."
fi

log "Removing MASQUERADE rules inside namespace ${NS} (matching -o ${VETH_NS_OUT})"

if ip netns list | grep -q "^${NS}\b"; then
    if command -v iptables >/dev/null 2>&1; then
        while ip netns exec "${NS}" iptables -t nat -S POSTROUTING 2>/dev/null | grep -q "MASQUERADE" | grep -q "\-o ${VETH_NS_OUT}"; do
            RULE=$(ip netns exec "${NS}" iptables -t nat -S POSTROUTING | grep "MASQUERADE" | grep "\-o ${VETH_NS_OUT}" | head -n1)
            RULE=${RULE/-A /-D }
            run "ip netns exec ${NS} iptables -t nat ${RULE}"
        done
    else
        log "WARNING: iptables not found, skipping NAT cleanup inside namespace."
    fi
else
    log "Namespace ${NS} not found, skipping NAT cleanup inside ns."
fi

###############################################################
# 6.1 Remove FORWARD rules between WAN_DEV and VETH_ROOT_OUT
###############################################################
log "Removing FORWARD rules between ${WAN_DEV} <-> ${VETH_ROOT_OUT}"

if command -v iptables >/dev/null 2>&1; then
    # 先删 in=WAN_DEV, out=VETH_ROOT_OUT 的规则
    while :; do
        # --line-numbers 输出格式: num pkts bytes target prot opt in out source destination
        LNS=$(iptables -nvL FORWARD --line-numbers 2>/dev/null \
            | awk -v wan="${WAN_DEV}" -v veth="${VETH_ROOT_OUT}" '$7==wan && $8==veth {print $1}' \
            | sort -rn)
        [ -z "$LNS" ] && break

        for ln in $LNS; do
            run "iptables -D FORWARD ${ln}"
        done
    done

    # 再删 in=VETH_ROOT_OUT, out=WAN_DEV 的规则
    while :; do
        LNS=$(iptables -nvL FORWARD --line-numbers 2>/dev/null \
            | awk -v wan="${WAN_DEV}" -v veth="${VETH_ROOT_OUT}" '$7==veth && $8==wan {print $1}' \
            | sort -rn)
        [ -z "$LNS" ] && break

        for ln in $LNS; do
            run "iptables -D FORWARD ${ln}"
        done
    done
else
    log "WARNING: iptables not found, skipping FORWARD chain cleanup."
fi

# Reset FORWARD policy
log "Setting root iptables FORWARD policy to ACCEPT"
if command -v iptables >/dev/null 2>&1; then
    run "iptables -P FORWARD ACCEPT || true"
else
    log "WARNING: iptables not found, cannot set FORWARD policy."
fi

###############################################################################
# 7. Delete namespace (this will implicitly delete ns-side veth)
###############################################################################

if ip netns list | grep -q "^${NS}\b"; then
    log "Deleting namespace ${NS}"
    run "ip netns delete ${NS}"
else
    log "Namespace ${NS} already absent, skipping."
fi

###############################################################################
# 8. Delete veth devices on root side
###############################################################################

for dev in "${VETH_ROOT_IN}" "${VETH_ROOT_OUT}"; do
    if ip link show "${dev}" >/dev/null 2>&1; then
        log "Deleting root veth device ${dev}"
        run "ip link delete ${dev}"
    else
        log "Root veth device ${dev} not found, skipping."
    fi
done

###############################################################################
# 9. (Optional) Clean /etc/iproute2/rt_tables entry
###############################################################################

if [[ -f /etc/iproute2/rt_tables ]]; then
    if grep -qE "^${RT_TABLE_ID}[[:space:]]+${RT_TABLE_NAME}\$" /etc/iproute2/rt_tables; then
        log "Removing '${RT_TABLE_ID} ${RT_TABLE_NAME}' from /etc/iproute2/rt_tables"
        run "sed -i.bak \"/^${RT_TABLE_ID}[[:space:]]\\+${RT_TABLE_NAME}\$/d\" /etc/iproute2/rt_tables"
    else
        log "Route table entry ${RT_TABLE_ID} ${RT_TABLE_NAME} not found in /etc/iproute2/rt_tables (skipping)."
    fi
else
    log "/etc/iproute2/rt_tables not found, skipping table cleanup."
fi

log "Rollback completed successfully."