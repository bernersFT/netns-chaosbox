#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# netns-chaosbox - Rollback Script (V1.0)
#
# This script reverts the changes made by the V1.0 deploy script:
#   - Removes tc qdisc on veth2
#   - Deletes policy routing rules
#   - Flushes the custom route table "chaosbox"
#   - Deletes the namespace "chaosbox" and its veth peers
#   - Optionally cleans up the custom table entry in /etc/iproute2/rt_tables
#
# NOTE:
#   This assumes the same parameters as the deploy script. If you change
#   names / IPs there, keep them in sync here.
###############################################################################

NS="chaosbox"
WAN_DEV="ens4"        # MUST match deploy.sh
WAN_DEV_IP="10.146.43.17"

VETH_ROOT_IN="veth0"
VETH_NS_IN="veth1"
VETH_ROOT_OUT="veth2"
VETH_NS_OUT="veth3"

RT_TABLE_ID=100
RT_TABLE_NAME="chaosbox"

NET_IN="10.0.0.0/30"
NET_OUT="10.0.1.0/30"

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

run() {
    echo "+ $*"
    eval "$@"
}

log "Starting netns-chaosbox rollback…"

###############################################################################
# 1. Remove tc qdisc from impairment interface (veth2)
###############################################################################

if ip link show "${VETH_ROOT_OUT}" >/dev/null 2>&1; then
    log "Removing qdisc from ${VETH_ROOT_OUT} (if present)"
    run "tc qdisc del dev ${VETH_ROOT_OUT} root 2>/dev/null || true"
else
    log "Interface ${VETH_ROOT_OUT} not found, skipping qdisc removal."
fi

###############################################################################
# 2. Remove policy routing rules (prefs 100/110/140/150/200)
###############################################################################

log "Removing policy routing rules (if present)"

for pref in 100 110 140 150 160 170 180 190 120 130  200; do
    # ip rule del pref will silently fail if not present, that's fine
    run "ip rule del pref ${pref} 2>/dev/null || true"
done

###############################################################################
# 3. Flush custom route table "chaosbox"
###############################################################################

log "Flushing routes in table '${RT_TABLE_NAME}'"
run "ip route flush table ${RT_TABLE_NAME} 2>/dev/null || true"

# Optional: also remove NET_IN/NET_OUT routes from main table if you want
log "Optionally cleaning direct routes for ${NET_IN} and ${NET_OUT} from main table"
run "ip route del ${NET_IN} dev ${VETH_ROOT_IN} 2>/dev/null || true"
run "ip route del ${NET_OUT} dev ${VETH_ROOT_OUT} 2>/dev/null || true"

###############################################################################
# 4. Clean up iptables rules
###############################################################################
# In deploy.sh you:
#   - Flushed all tables
#   - Added:
#       ip netns exec chaosbox iptables -t nat -A POSTROUTING -o veth3 -j MASQUERADE
#       iptables -t nat -A POSTROUTING -o ens4   -j MASQUERADE
#
# Here we try to remove those specific MASQUERADE rules.
###############################################################################

log "Removing MASQUERADE rules on root (matching -o ${WAN_DEV})"

# Delete MASQUERADE rules on WAN_DEV in root ns
while iptables -t nat -S POSTROUTING 2>/dev/null | grep -q "MASQUERADE" | grep -q "\-o ${WAN_DEV}"; do
    RULE=$(iptables -t nat -S POSTROUTING | grep "MASQUERADE" | grep "\-o ${WAN_DEV}" | head -n1)
    # Replace -A with -D to delete
    RULE=${RULE/-A /-D }
    run "iptables -t nat ${RULE}"
done

log "Removing MASQUERADE rule inside namespace ${NS} (matching -o ${VETH_NS_OUT})"

if ip netns list | grep -q "^${NS}\b"; then
    # Delete MASQUERADE rules on veth3 inside the namespace
    while ip netns exec "${NS}" iptables -t nat -S POSTROUTING 2>/dev/null | grep -q "MASQUERADE" | grep -q "\-o ${VETH_NS_OUT}"; do
        RULE=$(ip netns exec "${NS}" iptables -t nat -S POSTROUTING | grep "MASQUERADE" | grep "\-o ${VETH_NS_OUT}" | head -n1)
        RULE=${RULE/-A /-D }
        run "ip netns exec ${NS} iptables -t nat ${RULE}"
    done
else
    log "Namespace ${NS} not found, skipping NAT cleanup inside ns."
fi

###############################################################################
# 5. Delete namespace (this will implicitly delete veth1/veth3)
###############################################################################

if ip netns list | grep -q "^${NS}\b"; then
    log "Deleting namespace ${NS}"
    run "ip netns delete ${NS}"
else
    log "Namespace ${NS} already absent, skipping."
fi

###############################################################################
# 6. Delete veth devices on root side (veth0, veth2)
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
# 7. (Optional) Clean /etc/iproute2/rt_tables entry
###############################################################################
# If you prefer to leave "100 chaosbox" registered, comment this block out.
###############################################################################

if grep -qE "^${RT_TABLE_ID}[[:space:]]+${RT_TABLE_NAME}\$" /etc/iproute2/rt_tables; then
    log "Removing ${RT_TABLE_ID} ${RT_TABLE_NAME} from /etc/iproute2/rt_tables"
    sudo sed -i.bak "/^${RT_TABLE_ID}[[:space:]]\\+${RT_TABLE_NAME}\$/d" /etc/iproute2/rt_tables
else
    log "Route table entry ${RT_TABLE_ID} ${RT_TABLE_NAME} not found in /etc/iproute2/rt_tables (skipping)."
fi

log "Rollback completed successfully."