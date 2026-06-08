# 00 — Lab NSX 實況探測（2026-06-08）

直接打 NSX Manager (`192.168.114.13`) 與 inner vCenter (`192.168.114.11`) 的 live API 探測結果。
這份是後面所有決策的事實基礎。

---

## NSX 版本

```
GET https://192.168.114.13/api/v1/node/version
{
  "node_version": "9.1.0.0.25318227",
  "product_version": "9.1.0.0.25318225"
}
```

→ NSX 9.1，**有 VNA / DTGW 能力**。

---

## Default Transit Gateway = DTGW

```
GET /policy/api/v1/orgs/default/projects/default/transit-gateways/default
{
  "transit_subnets": ["100.64.0.0/21"],
  "is_default": true,
  "span": {
    "span_path": "/infra/network-spans/default--de45741b-...",
    "type": "ClusterBasedSpan"          ← 關鍵：ClusterBasedSpan = 分散式 (DTGW)
  },
  "external_ip_signaling_mode": "NONE",
  "id": "default",
  "display_name": "Default Transit Gateway"
}
```

→ lab 預設就建了一個 **DTGW**（跑在 ESXi cluster，非 edge）。
attachments 是空的（還沒接外部連線）。

---

## Default VPC Connectivity Profile 存在

```
GET /policy/api/v1/orgs/default/projects/default/vpc-connectivity-profiles
results[0]:
  id: "default"
  is_default: true
  transit_gateway_path: "/orgs/default/projects/default/transit-gateways/default"
  private_tgw_ip_blocks: ["/infra/ip-blocks/13a11ed1-..."]
  display_name: "Default VPC Connectivity Profile"
```

→ 已有 default profile 指向 default DTGW。沒有 `service_gateway` 區塊（= 沒接 edge，也沒接 VNA）。

---

## Edge cluster：沒有

```
GET /policy/api/v1/infra/sites/default/enforcement-points/default/edge-clusters
{ "results": [], "result_count": 0 }

GET /api/v1/edge-clusters
{ "result_count": 0 }

search resource_type:PolicyEdgeCluster → result_count: 0
search resource_type:PolicyEdgeNode    → result_count: 0
```

→ **完全沒有 edge cluster / edge node**。inventory `lab.yaml` 裡寫的
`vcf-m02-edge-cl01`（.70-.71 mgmt、.72-.73 uplink）只是規劃，實際沒建。
（Path B 要自己補部署。）

---

## VNA cluster：feature 在、未部署

```
GET /policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters
{ "results": [], "result_count": 0 }     ← 端點存在（200），但 0 個

search resource_type:VirtualNetworkApplianceCluster → 0
（其他別名 VirtualNetworkAppliance / NetworkAppliance / ServiceCluster ... 全 0）
```

→ NSX 9.1 支援 VNA，但 lab **還沒部署任何 VNA cluster**。
（Path A 要自己補部署。）

---

## Gateway connections：空

```
GET /policy/api/v1/infra/gateway-connections
{ "results": [], "result_count": 0 }
```

---

## 結論：兩條路線各缺什麼

| 路線 | lab 已有 | 還缺 |
|------|---------|------|
| **A. DTGW + VNA** | default DTGW、default VPC profile | **VNA cluster**、external IP block、把 VNA 接上 profile |
| **B. Edge + CTGW** | （幾乎從零）| **Edge cluster**、把 default TGW 改 centralized span、external IP block、VPC profile 綁 edge |

DTGW 路線阻力較小（順應 lab 預設）；Edge 路線要多部 edge cluster。

---

## 192.168.114.0/24 已佔用全表

| IP | 用途 |
|----|------|
| .5 | VCF Installer |
| .10 | SDDC Manager |
| .11 | inner vCenter |
| .12 | NSX node1 |
| .13 | NSX VIP |
| .14–.17 | nested ESXi 01–04 |
| .19 | VCFA 內部 VSP API VIP（勿動）|
| .20–.23 | VCFA 內部 VSP nodes（勿動）|
| .70–.71 | （規劃）NSX Edge mgmt |
| .72–.73 | （規劃）NSX Edge uplink |
| .75–.76 | VCF Ops + Collector |
| .77–.83 | VCF Automation + IP pool |
| .85 | License Server |
| .86 | vIDB |
| .87 | VCFA platform VIP |
| .200 | AD/DNS/NTP |
| .254 | VLAN 114 gateway |

→ VKS 用 `.101–.105`（CP）與 `.108/26`（external block）皆未衝突。
