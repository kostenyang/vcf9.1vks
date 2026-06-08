# Path A — UI 方法（DTGW + VNA）

NSX Manager (`https://192.168.114.13`) + inner vCenter (`https://kosten-vcf91-vc.rtolab.local`)。

---

## 1. External / Private IP Block（NSX Manager）

`Networking → IP Address Pools → IP Address Blocks → ADD`
- **External block**：Name `vcf-m02-vks-ext-ipblock`、CIDR `192.168.114.128/26`、Visibility **External**
- **Private TGW block**：Name `vcf-m02-vks-priv-tgw`、CIDR `172.30.0.0/16`、Visibility **Private**

---

## 2. VNA Cluster（NSX Manager 或 vCenter）

**NSX Manager**：`System → Fabric → VNA Cluster → ADD`
（或 vCenter `Configure → Networking → VNA Clusters`）

1. **建 cluster**：名稱 `vcf-m02-vna-01`、form factor `SMALL`、service type **VPC Services**、
   overlay transport zone 選 overlay TZ。
2. **ADD 第一台 VNA node**：
   - FQDN：`vcf-m02-vna01.rtolab.local`
   - Compute Manager：選 inner vCenter
   - Cluster：`vcf-m02-cl01`
   - Datastore：vSAN datastore
   - Management port group：VLAN 114 PG（`selab-dswitch-pg114` 或對應 segment）
   - Management network：Static，IP 從 mgmt 段挑一個未用的（如 `192.168.114.106`）/mask/gateway `.254`
   - 密碼：`VMware1!VMware1!`
3. （要 HA）**CLONE** 第二台：只填 FQDN + IP（如 `.107`）。
4. 部署，等狀態 **Up / Success**。

> 在這裡用 UI 部一台後，可 `GET .../virtual-network-appliances/<id>` 把真實 body 撈出來，
> 回填到 `Step1-Setup-DTGW.ps1` 的 placeholder（moref / ip_assignment_specs）。

---

## 3. DTGW External Connection + 綁 VNA（vCenter）

`vCenter → Networking → Network Connectivity → Configure Network Connectivity → Distributed Connectivity`
- VLAN ID：`114`
- Gateway CIDR：external connection 的 gateway（如 `192.168.114.128/26` 的 gateway）
- External IP Block：`vcf-m02-vks-ext-ipblock`
- Private Transit Gateway IP Block：`vcf-m02-vks-priv-tgw`（/16）
- 連線型態：**Distributed VLAN Connection**
- 選 **VNA cluster** `vcf-m02-vna-01`
- 開 **Default Outbound NAT**（啟用 DTGW SNAT）

---

## 4. 啟用 Supervisor（vCenter）

`Workload Management → Get Started`（實機驗證的 7 步 wizard，詳細截圖見 [../screenshots/README.md](../screenshots/README.md)）
1. **vCenter Server and Network**：vCenter 選 KOSTEN-VCF91-VC；networking stack 選 **VCF Networking with VPC**（只有 VPC / VDS 兩個選項，**無 NSX classic**）
2. **Supervisor location**：tab 選 **CLUSTER DEPLOYMENT**；Supervisor name `vcf-m02-supervisor`；左樹**先點 datacenter `vcf-m02-dc`** 才會在 COMPATIBLE 列出 `vcf-m02-cl01` → 選它
3. **Storage**：Control Plane / Ephemeral Disks / Image Cache 三個都選 `Management Storage Policy - Single Node`（FTT=0）
4. **Management Network**：Static，起始 IP `192.168.114.101`、mask `255.255.255.0`、gateway `.254`、DNS/NTP `192.168.114.200`、search domain `rtolab.local`
5. **Workload Network**：NSX Project `default`、VPC Connectivity Profile **`vcf-m02-vks-vpc-profile`（DTGW 那個）**、Service CIDR `10.96.0.0/23`、Default Private CIDR `172.30.0.0/24`
6. **Advanced Settings**：Content Library 指定 TKG subscribed library（`https://wp-content.vmware.com/supervisor/v1/latest/lib.json`）、Control Plane Size **Small**
7. **Ready to complete**：Review → **FINISH**，等 30–60 分鐘到 **Running**

---

## 5. per-VPC 開 LB

UI 沒這 toggle → 用 [`enable-vpc-lb.ps1`](enable-vpc-lb.ps1)。

---

## 6. 建 namespace + VKS cluster

UI：`Workload Management → Namespaces → New Namespace`（選 supervisor、命名 `vks-automation`、配 storage policy + permissions）。
VKS cluster 建議走 kubectl（[`../common/Step4-New-VksCluster.ps1`](../common/Step4-New-VksCluster.ps1)）。
