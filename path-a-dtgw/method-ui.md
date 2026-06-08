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

實機路徑（2026-06-08 驗證）：NSX Manager `System → Fabric → VNA Clusters → ADD CLUSTER`
（或 System Overview 點 "Virtual Network Appliance Clusters" 計數進去）。

1. **Add Cluster** 頁：
   - Cluster Name：`vcf-m02-vna-01`
   - Node Form Factor：下拉 Small（2vCPU/4GB）/ **Medium（4/8）** / Large（8/32）/ Extra Large（16/64）。
     ⚠️ **必須選 Medium 以上** —— 官方要求啟用 vSphere Supervisor 的 VNA 最小是 Medium，**Small 不支援**（實測踩過：先部 Small 要砍掉重部 Medium）。
   - 「Minimum one Virtual Network Appliance is required」→ 按 **ADD** 加 node。
   - NOTE：密碼由 SDDC Manager 自動產生/管理（不用自己填）。
2. **Add Node** 對話框（下拉自動帶 moref，不用查 ID）：
   - Node Name (FQDN)：`vcf-m02-vna01.rtolab.local`
   - Compute Manager：`kosten-vcf91-vc.rtolab.local`
   - vSphere Cluster：`vcf-m02-cl01`
   - Data Store：`vcf-m02-cl01-ds-vsan01`
   - Management Network：IP Assignment 選 **Static**
     - Management CIDR：`192.168.114.106/24`（輸入後按 Enter 變 chip）
     - Default Gateway：`192.168.114.254`（同樣按 Enter 變 chip）← 兩個都變 chip 後 APPLY 才會亮
     - Port Group：`vcf-m02-cl01-vds01-pg-mgmt`（自動帶）
   - **APPLY**
3. 回 Add Cluster 頁，node 列表出現該 node → **SAVE** 開始部署。
4. VNA Clusters 清單：Status **In Progress**（橘）→ 等 OVA 部署 + 開機 + 註冊（nested 約 15–30 分鐘）→ **Up / Success**。
5. （要 HA）再 **ADD** 或 **CLONE** 第二台（`.107`）。

> 實機驗證：UI 建出來的物件 = `appliance_form_factor=SMALL`、`service_type=VPC_SERVICES`，
> 與 [`Step1-Setup-DTGW.ps1`](Step1-Setup-DTGW.ps1) 反推的 schema 一致。
> Poll 狀態：`GET /policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters`

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
