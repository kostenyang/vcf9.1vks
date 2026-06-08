# 03 — Edge Cluster + Centralized TGW 研究（Edge 路線）

把 default Transit Gateway 從 distributed 改成 centralized（edge-based），需要先部
NSX Edge cluster + Tier-0，再讓 VPC Connectivity Profile 綁 edge cluster。

---

## 關鍵架構事實

- **一個 Project 只有一個 TGW**：不要建第二個，是改 default TGW 的連外方式 / 在 VPC profile 綁 edge。
- **Centralized = edge-based**：TGW 的 service router 跟 Tier-0 SR 同住在 Edge VM 上。
  VKS 要 **Tier-0 Active/Standby**（NAT 才有效；Active/Active 不支援 NAT）。
- VCF 9.x 把 edge + T0 + centralized TGW 包成 vCenter 的 **guided "Network Connectivity" wizard**
  （`Networks → Network Connectivity → Configure Network Connectivity → Centralized`），一次部完。
  SDDC Manager `POST /v1/edge-clusters` 仍可用，但 9.x 主推 guided 流程。

---

## STEP 1 — 部 Edge cluster（三方法）

### 方法 A — NSX Policy / MP REST API
兩段式：先部 edge transport node（MP API），再 policy 建 edge cluster。

1. 部 edge transport node（會經 compute manager 部 Edge VM）：
   ```
   POST /api/v1/transport-nodes
   node_deployment_info:
     resource_type: EdgeNode
     deployment_config:
       form_factor: MEDIUM
       vc_id / compute-manager id, datastore, mgmt + TEP + uplink port groups
     node_settings: { hostname, ... }
   ```
2. policy 建 edge cluster：
   ```
   PUT /policy/api/v1/infra/sites/default/enforcement-points/default/edge-clusters/{id}
   body: member edge transport-node paths + edge cluster profile
   ```

### 方法 B — NSX Manager UI
`System → Fabric → Nodes → Edge Transport Nodes → Add Edge Node`
- FQDN、form factor **MEDIUM**、credentials
- compute manager (vCenter)、cluster、datastore
- mgmt 介面：PG + static IP/gateway
- TEP：VLAN + IP pool（或 DHCP）；uplink/teaming → fp-eth0/fp-eth1
- 部 ≥2 台 → `Edge Clusters → Add Edge Cluster` 把兩台加入

### 方法 C — VCF guided wizard / SDDC Manager API（VCF 9.1 推薦）

**Guided vCenter wizard**（9.x 主推）：
`vCenter → Networks → Network Connectivity → Configure Network Connectivity → Centralized Connectivity`
→ 一次部 edge cluster + ≥2 edge VM + Tier-0 (Active/Standby) + centralized TGW + IP blocks。

**SDDC Manager API**（先 validate）：
```
POST /v1/edge-clusters/validations   （先驗證）
POST /v1/edge-clusters
{
  "edgeClusterName": "vcf-m02-edge-cl01",
  "edgeClusterType": "NSX-T",
  "edgeFormFactor": "MEDIUM",
  "tier0ServicesHighAvailability": "ACTIVE_STANDBY",   ← VKS 要 A/S
  "mtu": 1600,
  "asn": 65051,
  "edgeNodeSpecs": [
    {
      "edgeNodeName": "kosten-vcf91-en01.rtolab.local",
      "managementIP": "192.168.114.70/24",
      "managementGateway": "192.168.114.254",
      "edgeTepGateway": "192.168.117.1",
      "edgeTep1IP": "192.168.117.28/24",
      "edgeTep2IP": "192.168.117.29/24",
      "edgeTepVlan": 117,
      "clusterId": "<vsphere-cluster-uuid>",
      "uplinkNetwork": [
        { "uplinkVlan": 114, "uplinkInterfaceIP": "192.168.114.72/24", "peerIP": "192.168.114.254/24", "asnPeer": 65000 }
      ]
    },
    { "edgeNodeName": "kosten-vcf91-en02.rtolab.local", "managementIP": "192.168.114.71/24", ... "edgeTep1IP":"192.168.117.30/24","edgeTep2IP":"192.168.117.31/24" }
  ],
  "tier0RoutingType": "STATIC",
  "tier0Name": "vcf-m02-t0",
  "tier1Name": "vcf-m02-t1"
}
```
auth：`POST /v1/tokens`（administrator@vsphere.local / VMware1!VMware1!）拿 Bearer。

> lab IP 對應 inventory：edge mgmt .70/.71、uplink .72/.73、TEP 117.28-31、TEP VLAN 117、uplink VLAN 114。
> lab T0 用 STATIC routing（無 BGP peer），所以 uplink 不填 asnPeer 也可，T0 設 static default route 指 .254。

---

## STEP 2 — Centralized TGW + VPC Connectivity Profile

### 真實 schema（從 lab OpenAPI，見 [04](04-nsx-schemas.md)）
```
TransitGateway:
  transit_subnets: [string]
  span: BaseSpan { type: ClusterBasedSpan | ZoneBasedSpan }
  external_ip_signaling_mode: NONE | IPV4

TransitGatewayAttachment:
  connection_path: string  REQ      ← 指向 Tier-0 external connection
  route_advertisement_rules: [...]
  urpf_mode: NONE | STRICT

VpcConnectivityProfile:
  transit_gateway_path: string  REQ
  external_ip_blocks: [string]
  private_tgw_ip_blocks: [string]    ← VKS 要求 /16
  service_gateway: VpcServiceGatewayConfig {
    enable: boolean
    edge_cluster_paths: [string]     ← Centralized 的關鍵：填 edge cluster
    nat_config: VpcNatConfig
  }
```

### 切換 distributed → centralized 的做法
**重點**：沒有 `span_type=EDGE_BASED` 這種 flag。Centralized 是靠
1. 建 **TransitGatewayAttachment**，`connection_path` 指向 Tier-0 的 external connection（TGW SR 就跟 T0 SR 同住 edge）；
2. **VPC Connectivity Profile** 的 `service_gateway.enable=true` + `edge_cluster_paths=[<edge-cluster>]`。

```
PUT /policy/api/v1/orgs/default/projects/default/transit-gateways/default/attachments/t0-attach
{ "resource_type":"TransitGatewayAttachment", "connection_path":"/infra/tier-0s/vcf-m02-t0" }

PATCH /policy/api/v1/orgs/default/projects/default/vpc-connectivity-profiles/vcf-m02-vks-vpc-profile
{
  "resource_type":"VpcConnectivityProfile",
  "transit_gateway_path":"/orgs/default/projects/default/transit-gateways/default",
  "external_ip_blocks":["/infra/ip-blocks/vcf-m02-vks-ext-ipblock"],
  "private_tgw_ip_blocks":["/infra/ip-blocks/vcf-m02-vks-priv-tgw"],
  "service_gateway":{ "enable":true, "edge_cluster_paths":["<edge-cluster-path>"] }
}
```

> 注意（sdn-warrior）：若 VPC 已在 cluster 上 active，re-span 會失敗 → 趁還沒建 workload 時做（你 lab 剛好乾淨）。
> HA mode 繼承 Tier-0（A/S → NAT 可用；A/A → 無 NAT）。

---

## STEP 3 — Supervisor 啟用（centralized 模式）

跟 DTGW 路線同一個 API（`POST /api/vcenter/namespace-management/supervisors`），
差別只在指向的 **VPC Connectivity Profile 是 centralized 那個**（service_gateway 綁 edge）。
Supervisor spec 本身不分 DTGW/CTGW — 它只認 project + profile。

- UI：`右鍵 cluster → Activate Supervisor → Advanced → "VCF Networking with VPC"`
  → Workload Network 選 default project + centralized VPC profile。
- provider：`NSX_VPC`（不是舊的 `NSXT`）。

---

## 來源

- evoila VCF 9 NSX VPC Part 1 centralized TGW: https://evoila.com/us/blog/vcf-9-nsx-vpc-part-1-centralized-transit-gateway/
- VCF blog — VPC Centralized + Guided Edge: https://blogs.vmware.com/cloud-foundation/2025/06/25/vpc-centralized-network-connectivity-with-guided-edge-deployment/
- vStellar Part 4 Edge deploy: https://vstellar.com/2025/07/vcf-9-part-4-nsx-edge-cluster-deployment/
- vStellar Part 6 Network Connectivity: https://vstellar.com/2026/05/vcf-9-1-home-lab-series-part-6-configure-network-connectivity/
- williamlam NSX VPC + Supervisor: https://williamlam.com/2025/08/ms-a2-vcf-9-0-lab-configuring-vsphere-supervisor-with-nsx-vpc-networking.html
- Broadcom TechDocs Transit Gateways: https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/advanced-network-management/administration-guide/virtual-private-cloud-in-nsx/transit-gateways.html
- Broadcom Developer NSX REST `CreateOrReplaceTransitGateway`: https://developer.broadcom.com/xapis/nsx-t-data-center-rest-api/latest/method_CreateOrReplaceTransitGateway.html
- SDDC Manager edge-cluster API body (lab2prod): https://www.lab2prod.com.au/2021/09/deploy-nsx-tedge-clusters-using-api.html
- **權威 schema**：lab `GET /policy/api/v1/spec/openapi/nsx_policy_api.json`
