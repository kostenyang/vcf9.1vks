# Path B — UI 方法（Edge + Centralized TGW）

VCF 9.x 主推 **vCenter guided Network Connectivity wizard**：一個精靈把 edge cluster +
Tier-0 + centralized TGW 一次部完。

---

## 1. Guided Edge + Centralized TGW（vCenter）

`vCenter → Networks → Network Connectivity → Configure Network Connectivity → Centralized Connectivity`

精靈一次部：edge cluster + 2 台 edge VM + Tier-0 (Active/Standby) + centralized TGW + IP blocks。
每台 edge 填：
- FQDN：`kosten-vcf91-en01.rtolab.local` / `en02`
- vSphere cluster：`vcf-m02-cl01`
- datastore：vSAN datastore
- form factor：**MEDIUM**
- 管理介面：mgmt PG（VLAN 114）、IP `192.168.114.70` / `.71`、gateway `.254`
- Edge TEP：VLAN `117`、IP pool `192.168.117.28–.31`、gateway `192.168.117.1`
- Uplink：VLAN `114`、IP `192.168.114.72` / `.73`
- Tier-0：**Active/Standby**、routing **STATIC**（default route → `192.168.114.254`）
  - （若要 BGP：填 local ASN + peer ASN/IP，本 lab 用 STATIC 即可）

External IP block：`192.168.114.128/26`；Private TGW block：`172.30.0.0/16`（/16）。

> 替代：NSX Manager UI `System → Fabric → Nodes → Edge Transport Nodes → Add Edge Node`
> 手動部 2 台再建 edge cluster；T0 在 `Networking → Tier-0 Gateways → ADD`（HA Active/Standby）。

---

## 2. VPC Connectivity Profile（綁 edge）

`NSX Manager → (選 default project) → VPCs → Profiles → VPC Connectivity Profile → ADD`
- Transit Gateway：default（已變 centralized）
- External IP Blocks：`vcf-m02-vks-ext-ipblock`
- Private-TGW IP Blocks：`vcf-m02-vks-priv-tgw`（/16）
- **VPC Service Gateway → Edge Cluster**：選剛部的 edge cluster；**N-S Services 開**；可開 Default Outbound NAT

---

## 3. 啟用 Supervisor（vCenter）

實機 7 步 wizard 跟 Path A 完全一樣（`Workload Management → Get Started`，詳見
[../screenshots/README.md](../screenshots/README.md) 與 [Path A method-ui §4](../path-a-dtgw/method-ui.md)）。
**唯一差別在 Step 5 Workload Network**：VPC Connectivity Profile 選 **centralized 那個**
（`vcf-m02-vks-vpc-profile`，其 service_gateway 綁了 edge cluster）。

其餘（Step1 選 VCF Networking with VPC、Step2 cluster deployment 選 vcf-m02-cl01、
Step3 storage、Step4 CP IP `.101`、Service CIDR `10.96.0.0/23`、Step6 Content Library）皆同 Path A。

---

## 4. namespace + VKS cluster

同 Path A：`Workload Management → Namespaces → New Namespace`（`vks-automation`），
VKS cluster 走 kubectl（[`../common/Step4-New-VksCluster.ps1`](../common/Step4-New-VksCluster.ps1)）。
