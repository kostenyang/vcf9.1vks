# 01 — DTGW vs Centralized TGW 架構比較

VCF 9.1 NSX VPC 有兩種 Transit Gateway 連線模型，VKS Supervisor 都支援。

---

## 概念

NSX VPC 裡，每個 **Project 只有一個 Transit Gateway**（建 project 時自動帶）。
它的「連外方式」決定是 distributed 還是 centralized：

```
        Tenant VPC ── Transit Gateway ── External Connection ── 實體網路
                          │
              ┌───────────┴───────────┐
       Distributed (DTGW)      Centralized (CTGW)
       跑在 ESXi host           跑在 NSX Edge VM
       stateful 靠 VNA          stateful 靠 Edge
```

---

## 兩者差異

| 面向 | Distributed (DTGW) | Centralized (CTGW) |
|------|--------------------|--------------------|
| Service Router 跑在哪 | ESXi host（分散式）| NSX Edge VM（集中式）|
| 要不要 Edge cluster | ❌ | ✅（≥2 edge VM）|
| SNAT（私網連外）| 9.0 沒有；9.1 靠 **VNA** | Edge 內建 |
| Load Balancer | 靠 **VNA**（9.1 新）| Edge L4 LB |
| DHCP / NAT | VNA（9.1）| Edge |
| BGP / ECMP 到實體 | 受限 | 完整（Active/Active 最多 8 SR）|
| east-west 流量 | 全分散在 host，效能好 | 經 edge |
| 設計複雜度 | 流量路徑較難追 | 傳統、成熟 |
| HA 需求 | T0/連線 Active/Standby | T0 Active/Standby（給 VKS NAT）|

---

## 對 VKS Supervisor 的意義

Supervisor 需要 **LoadBalancer**（kube-apiserver VIP + Service type=LoadBalancer）+ **SNAT**（pod 連外）。

- **DTGW 路線**：純 DTGW 給不了 LB/SNAT → VCF 9.1 引入 **VNA cluster** 補上 stateful 服務。
  → 所以 DTGW 路線 = DTGW（已有）+ **VNA cluster**（要部）。
- **CTGW 路線**：Edge node 本身就提供 LB/SNAT。
  → 所以 Edge 路線 = **Edge cluster**（要部）+ 把 TGW 改 centralized span。

---

## 關鍵實作差異點（從 live schema 確認）

DTGW vs CTGW 的差別**不在 TransitGateway 的 span type**（兩者 `BaseSpan.type` 都只能是
`ClusterBasedSpan` / `ZoneBasedSpan`），而在 **VPC Connectivity Profile 的 `service_gateway`**：

```
VpcConnectivityProfile.service_gateway (VpcServiceGatewayConfig):
  enable: boolean
  edge_cluster_paths: [ ... ]   ← Centralized 才填 edge cluster
  nat_config: VpcNatConfig
  qos_config: GatewayQosProfileConfig
```

- **Centralized**：`service_gateway.enable=true` + `edge_cluster_paths=[<edge-cluster>]`
- **Distributed + VNA**：透過 **Distributed VLAN Connection** 把 external connection + external IP block + **VNA cluster** 綁起來，並開 default outbound NAT。

詳見 [02-vna-research.md](02-vna-research.md) 與 [03-edge-ctgw-research.md](03-edge-ctgw-research.md)。

---

## 怎麼選（給 rtolab）

| 你的情況 | 建議 |
|---------|------|
| 想順應 lab 預設、host 記憶體/CPU 夠、想測 9.1 新東西 | **Path A (DTGW+VNA)** |
| 想要傳統成熟、要 BGP/ECMP 對接實體、之後要跑多 workload domain | **Path B (Edge+CTGW)** |
| 兩個都想測（你的需求）| 先 A 後 B，或分兩個 Supervisor 試 |

> 注意：同一個 default project 的 TGW 只有一個。要在同一 project 同時測兩種 span 會互斥；
> 建議測完一種、清掉再測另一種，或 Path B 另開一個 NSX Project。
