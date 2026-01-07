# **netns-chaosbox**

### *Deterministic Linux Network Impairment Sandbox using Network Namespaces, veth pairs, policy routing, and NAT*

<font color=red>`netns-chaosbox`</font> is an out-of-the-box network impairment simulation platform—a fully self-contained, production-grade framework that emulates real-world network degradation conditions (latency, jitter, packet loss, bandwidth limitations, packet reordering, corruption, and blackhole scenarios) **without modifying the host network stack**.

It accomplishes this through the use of **Linux network namespaces**, **veth pairs**, **policy routing**, and **multi-stage NAT**, enabling any application (VPN services, proxies, microservices, client test agents, etc.) to be routed through a controlled “chaos pipeline”.

Technically, Chaosbox is designed for Dev & QA teams to test service resilience and reliability under unstable or impaired network conditions.

Typically, the physical connection architecture is as follows:

``` scss
                +-----------------------+
client → vpn →  |   netns-chaosbox      | → your service
                +-----------------------+
```

You can configure various network parameters on the Chaosbox node, including latency, jitter, packet loss, bandwidth limits, packet reordering, and all other impairment types supported by **tc**.

Finally, Chaosbox is not only a practical solution, but also an excellent learning resource for understanding Linux networking. During its development, we encountered and resolved several classical issues related to network forwarding. You can reproduce these scenarios yourself—it’s both educational and fun. I’m glad to assist you if needed.

## HOW TO USE
``` shell
git clone https://github.com/bernersFT/netns-chaosbox.git
cd netns-chaosbox
chmod +x install.sh 
sudo ./install.sh 
```
DONOT FORGET TO EDIT 'chaosbox.conf'

# **1. Why netns-chaosbox is Unique**

|Feature / Capability|**netns-chaosbox**|tc netem|Toxiproxy|Pumba|Chaos Mesh|Istio Fault Injection|WANem|
|---|---|---|---|---|---|---|---|
|**Impairment Direction**|**True bidirectional (TX + RX)**|Mostly outbound only|Outbound only (proxy)|Outbound only|Bidirectional|Bidirectional|Bidirectional|
|**Ingress Processing (PREROUTING)**|**✔ Fully supported**|✘|✘|✘|✔|✔|✔|
|**Egress Processing (POSTROUTING)**|**✔ Fully supported**|✘|✘|✘|✔|✔|✔|
|**NAT / SNAT / MASQUERADE Support**|**✔ Full NAT pipeline (double NAT)**|✘|✘|✘|Partial|✔|✔|
|**Policy Routing (RPDB)**|**✔ Advanced (multiple tables, rules)**|✘|✘|✘|✘|Partial|✘|
|**Realistic Kernel Routing Simulation**|**✔ Highest realism**|Medium|Low|Medium|Medium|Medium|Medium|
|**Asymmetric Routing Simulation**|**✔ Fully supported**|✘|✘|✘|Partial|Partial|Partial|
|**VPN / Tunnel Support (SoftVPN / L2TP / IPSec)**|**✔ Fully compatible**|✘|✘|✘|✘|✘|✘|
|**Virtual Topology (veth networks)**|**✔ Arbitrary topology**|✘|✘|✘|Partial|✘|✘|
|**Layer of Operation**|**Linux Kernel L2/L3**|Kernel L3|Userspace TCP/UDP proxy|Docker layer|Kubernetes CNI|L7/Envoy|FreeBSD kernel|
|**Standalone Usability**|**✔ Excellent**|✔|✔|✔|✘|✘|✘|
|**Requires Docker?**|No|No|Yes|Yes|Yes|No||
|**Requires Kubernetes?**|No|No|No|No|Yes|Yes||
|**Typical Use Cases**|**System-level WAN simulation / VPN testing / kernel routing / protocol R&D**|Quick per-interface tests|App-layer chaos|Container chaos|Micro-service chaos|Mesh routing errors|WAN path simulation|
|**Difficulty Level**|High (kernel & routing)|Low|Low|Medium|Medium|Medium|Medium|
|**Flexibility**|**★★★★★ Highest**|★☆☆☆☆|★★☆☆☆|★★☆☆☆|★★★☆☆|★★★☆☆|★★★☆☆|
|**Open Source**|✔|✔|✔|✔|✔|✔|✔|

**netns-chaosbox is the only open-source tool that:**

- Simulates **both outbound and inbound** network impairment
- Applies **full kernel NAT logic** (PREROUTING ⇆ POSTROUTING, reverse SNAT)
- Supports **policy routing, custom route tables, asymmetric flows**
- Works natively with **SoftVPN, WireGuard, OpenVPN, IPSec, tunnels**
- Creates a **full virtual WAN path inside Linux** using namespaces + veth
- Emulates **realistic multi-hop routing** and **double NAT** behavior
- Provides **system-level, kernel-accurate WAN simulation** without Docker or Kubernetes

It is far more than "just tc netem" or "just a proxy";  
it is a **miniature WAN environment** inside your machine.



# **2. Components**

| Component                            | Description                                                   |
| ------------------------------------ | ------------------------------------------------------------- |
| Ubuntu server 22.04                  |                                                               |
| **SoftEther VPN**                    | collect network flow data from client                         |
| **Namespace (`chaosbox`)**           | Isolated "blackhole" environment simulating impaired networks |
| **veth0/veth1**                      | Entry link between root → namespace                           |
| **veth2/veth3**                      | Exit link and impairment point                                |
| **tc netem**                         | Network impairment engine                                     |
| **iptables NAT (inside namespace)**  | SNAT for traffic exiting namespace                            |
| **iptables NAT (root)**              | SNAT for traffic leaving via WAN                              |
| **Policy routing (`ip rule`)**       | Forces traffic through chaos pipeline                         |
| **Custom routing table (table 100)** | Outbound redirection to namespace                             |

# **3. Architecture Overview**

``` scss
                      +------------------------------------+
                      |          root namespace            |
                      |------------------------------------|
   Client/App         |                                    |
   (SoftEther, etc.)  |          Policy Routing            |
        │             |         +---------------+          |
        │             |         |  table=main   |          |
        ▼             |         |  table=chaos  |          |
                      |         +---------------+          |
                      |                 │                  |
                      |                 ▼                  |
                      |         +--------------+           |
                      |         |   veth0      |           |
                      |         |   10.0.0.1   |           |
                      |         +------+--------+          |
                      +------------------|-----------------+
                                         |
                                         | veth-pair
                                         |
                      +------------------|-----------------+
                      |           chaosbox namespace       |
                      |------------------------------------|
                      |   +-------------+    +-----------+ |
                      |   |  veth1      |    |  veth3    | |
                      |   | 10.0.0.2    |    | 10.0.1.2  | |
                      |   +------+------+    +-----+-----+ |
                      |          ^                   |     |
                      |          |                   |     |
                      |      routing: default via 10.0.1.1 |
                      |                                    |
                      +------------------------------------+
                                         |
                                         | veth-pair
                                         v
                      +------------------------------------+
                      |          root namespace            |
                      |------------------------------------|
                      |         +-------------+            |
                      |         |  veth2      |            |
                      |         | 10.0.1.1    |            |
                      |         +------+------ +-----------+
                      |                | (traffic impairment)
                      |   tc netem --> | delay / loss / jitter
                      |                ▼                   |
                      |        +---------------+           |
                      |        |    ens4       |           |
                      |        | (WAN uplink)  |           |
                      |        +-------+-------+           | 
                      |                |                   | 
                      +----------------|--------------------+
                                       |
                                       v
                                    Internet
```

# 4. **Outbound Path (Root → Chaosbox → Root → Your service)**

```scss
┌──────────────────────────────┐
│        Root Namespace        │
└──────────────────────────────┘
local process (e.g., ping 8.8.8.8)
        │
        ▼
[ OUTPUT chain ] (raw → mangle → filter → nat OUTPUT)
    • You can MARK packets here for policy routing
        │
        ▼
Route lookup (RPDB → main/chaosbox tables)
    • Chooses veth0 due to rule pref 200
        │
        ▼
[ POSTROUTING ] (root nat table)
    • No SNAT (this is internal traffic to namespace)
        │
        ▼
veth0 (root)

─────────── Cross into namespace ────────────

┌──────────────────────────────┐
│       chaosbox Namespace     │
└──────────────────────────────┘
veth1 (ingress)
        │
        ▼
[ PREROUTING ] (ns nat table)
    • No DNAT
        │
        ▼
Route lookup (inside chaosbox)
    • default via 10.0.1.1 → veth3
        │
        ▼
[ POSTROUTING ] (ns nat table)
    • MASQUERADE on veth3
      src becomes **10.0.1.2**
        │
        ▼
veth3 → veth2  (back to root)

────────── Back to Root NS ──────────

veth2 (ingress)
        │
        ▼
[ PREROUTING ] (root nat)
        │
        ▼
[ FORWARD ] (root filter)
        │
        ▼
[ POSTROUTING ] (root nat)
    • MASQUERADE out WAN
      src 10.0.1.2 → 10.146.43.17
        │
        ▼
ens4 → Internet
```

# **5. Inbound Path (YOUR Service → Root → Chaosbox → Root → App)**

```scss
Internet
        │
        ▼
ens4 (ingress root)

──────── Root Namespace ────────

[ PREROUTING ] (root nat)
        │
        ▼
Route lookup (RPDB)
    • dst = 10.0.1.2 → veth2
        │
        ▼
[ FORWARD ] (root filter)
        │
        ▼
[ POSTROUTING ] (ns nat)
    • No SNAT on veth2 (internal traffic)
        │
        ▼
veth2 → veth3 (namespace)

──────── chaosbox Namespace ────────

veth3 ingress
        │
        ▼
[ PREROUTING ] (ns nat)
    • Reverse-SNAT:
      dst 10.0.1.2 → 10.146.43.17
        │
        ▼
Route lookup
    • dst=10.146.43.17 → veth1
        │
        ▼
[ POSTROUTING ] (ns nat)
    • No SNAT on veth1 (internal traffic)
        │
        ▼
veth1 → veth0 → root

──────── Back to root ─────────

[ PREROUTING ] (root nat)
    • No SNAT on veth0
        │
        ▼
Route lookup (local)
        │
        ▼
[ INPUT ] (root filter)
        │
        ▼
Local application (softvpn / ping process)
```

# **6. Key Features**

-   **Outbound & inbound symmetrical impairment**
-   **Two-stage NAT (namespace + root)** for correct return flows
-   **Policy routing** (multiple `ip rule` layers)
-   **Deterministic traffic path** (directly observable via tcpdump, perf, or eBPF)
-   **Uber-clean rollback** (does not harm the host network)
-   **100% reproducible** — ideal for networking R&D

# **7. Deployment Script Summary**

### **Performs:**

- Creates namespace
- Creates 2 veth pairs
- Assigns IPs and brings interfaces up
- Adds namespace routing:
  - default via `veth3 → 10.0.1.1`
  - host route to WAN_IP via `veth1`
- Adds root-level routing
- Enables IP forwarding
- Creates custom routing table `chaosbox` (ID 100)
- Adds policy routing rules:
  - bypass management networks
  - ensure correct backflow
  - default send all other traffic → namespace
- Applies iptables NAT in **both root and namespace**
- Applies NETEM on `veth2`

------

# **8. Bidirectional Forwarding & NAT Details (Important)**


## **8.1 Outbound Flow (SNAT in namespace)**

When packets **leave chaosbox namespace via `veth3`**:

```
POSTROUTING (namespace nat table):
  -A POSTROUTING -o veth3 -j MASQUERADE
```

This rewrites:

```
src: 10.146.43.17 → src: 10.0.1.2   # veth3's IP inside the namespace
```

Why needed?
 Without this SNAT, return packets from the Internet would go directly back to 10.146.43.17 in the root namespace, bypassing the chaosbox on the way
back. MASQUERADE forces replies to target 10.0.1.2 first so that they must traverse veth2/veth3 and the namespace again, giving you **bidirectional**
impairment.

------

## **8.2 Outbound Flow (SNAT on root WAN)**

After impairment, packets exit via root interface:

```
POSTROUTING (root nat table):
  -A POSTROUTING -o ens4 -j MASQUERADE
```

This rewrites:

```
src: 10.0.1.2 → src: WAN_IP (10.146.43.17)
```

Required so that **Internet replies return to the correct host**.

------

## **8.3 Inbound Flow (policy routing is critical)**

Returning packets arrive at `ens4`:

```
dest: 10.146.43.17 → root kernel → reverse NAT
dest: 10.0.1.1 → route lookup → veth2
```

Policy rules ensure reverse packets **follow EXACT reverse path**:

| Pref | Rule                     | Purpose                              |
| ---- | ------------------------ | ------------------------------------ |
| 100  | to 10.146.0.0/16 → main  | Bypass chaos                         |
| 110  | to 10.145.0.0/16 → main  | Bypass chaos                         |
| 140  | to 10.0.1.0/30 → main    | Ensure reply reaches veth2           |
| 150  | from 10.0.1.2 → main     | Namespace return traffic goes to WAN |
| 200  | default → table chaosbox | All else forced to chaos pipeline    |

```bash
~# ip rule show
0:      from all lookup local
100:    from all to 10.146.0.0/16 lookup main
110:    from all to 10.145.0.0/16 lookup main
140:    from all to 10.0.1.0/30 lookup main
150:    from 10.0.1.2 lookup main
200:    from all lookup chaosbox
32766:  from all lookup main
32767:  from all lookup default
```

These rules produce:
-   Correct reverse forward path
-   No routing loops
-   No duplicate packets
-   Perfect symmetry with outbound path

------

# **9. Traffic Path with iptables & routing**

## **Outbound Packet Example**

Packet generated by application:

```
Client → vpn → root namespace
```

**Root → Namespace entry**

```
[Routing]
  dst != management network
  dst != 10.0.1.0/30
→ ip rule pref 200
→ lookup table chaosbox
→ default via 10.0.0.2 dev veth0

# ~# ip route show table chaosbox
# default via 10.0.0.2 dev veth0
```

**Namespace**

```
veth1 receive frame
ROUTING → default via 10.0.1.1
→ veth3 output
POSTROUTING (namespace nat): SNAT to 10.0.1.2
```

**Root exits**

```
veth2 → qdisc netem
veth2 → root routing → ens4
POSTROUTING (root nat): SNAT to WAN_IP
→ Internet
```

------

## **Inbound Packet Example**

Internet sends:

```
src: 8.8.8.8 → dst: WAN_IP
```

Root NAT → restores:

```
dst: 10.0.1.2
```

Routing:

```
Matches rule: to 10.0.1.0/30 → lookup main
→ veth2
```

Namespace:

```
veth3 receive
PRETROUTING (ns nat): DNAT 10.0.1.2 → 10.146.43.17
route → veth1
→ veth1
```

Back to root → application → client.

------


## **10. Verification Tools**

### **tcpdump**

```
ip netns exec chaosbox tcpdump -ni veth1
ip netns exec chaosbox tcpdump -ni veth3
tcpdump -ni veth0
tcpdump -ni veth2
```

### **perf / eBPF**

```
perf trace -e net:net_dev_queue -e net:netif_receive_skb  ping 8.8.8.8 -c1>/dev/null
```

Useful for verifying forward paths.

------

## **11. Example Use Cases**

| Use Case                        | Description                                  |
| ------------------------------- | -------------------------------------------- |
| Mobile network simulation       | Simulate 3G/4G/5G RTT/loss/drop              |
| VPN stress testing              | Test reconnection behavior under flaky links |
| Chaos engineering               | Inject deterministic failure domains         |
| Cloud app R&D                   | Test long-haul routing behavior              |
| Gaming & latency-sensitive apps | Study packet jitter and bufferbloat          |
| Research & teaching             | Network namespaces + routing + NAT concepts  |

------
