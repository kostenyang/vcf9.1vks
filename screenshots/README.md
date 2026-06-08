# 實機 UI 截圖walkthrough（vCenter Activate Supervisor wizard）

2026-06-08 在 live vCenter (`kosten-vcf91-vc.rtolab.local`) 實際走 wizard 截圖。
截圖檔存在操作端瀏覽器（"RTO LAB" Chrome）機器上；本檔記錄每步**實機驗證**的內容
（修正了先前憑研究寫的 method-ui.md，wizard 實際步驟與我原本寫的不同）。

> nested-on-nested vCenter UI 偏慢，Storage 步驟的 SPBM dropdown 會讓 renderer 卡住，
> 截圖到 Step 3 後 renderer 凍結；Step 4-7 用實機驗證到的欄位以文字補完（見下）。

---

## 入口：Supervisor Management

`https://kosten-vcf91-vc.rtolab.local/ui/app/workload-platform/`

- 標題 **Supervisor Management**，Namespaces 清單 **No items found**（確認尚無 user Supervisor）。
- 兩個按鈕：**GET STARTED**（開 wizard）、**GET STARTED WITH CONFIG**（匯入 config）。
- Prerequisites 三張卡：
  1. **Assign Content Library with Latest Supervisor Images**
  2. **Network Support** — 「You can select between two networking stacks … vSphere Distributed Switch (VDS) and **VCF Networking with VPC** are supported.」
  3. **HA and DRS Support** — cluster 要開 HA + DRS 全自動。

---

## Step 1 — vCenter Server and Network

- 提示：**「There is no assigned Content Library for Supervisor releases」**（沒指定 content library 會跳）。
- Select a vCenter Server system：**KOSTEN-VCF91-VC.RTOLAB.LOCAL (SUPPORTS NSX)**
- Select a networking stack（**只有兩個選項**）：
  - **VCF Networking with VPC (recommended)** ← 兩條路線（DTGW / Edge）都選這個
  - **vSphere Distributed Switch (VDS)**
  - ⚠️ **沒有獨立的「NSX (classic)」選項** — 9.1 NSX 一律走 VPC；DTGW vs Centralized 是看你綁的 VPC Connectivity Profile，不是這裡選。
- 右側架構圖：Physical Router → External IP Blocks → Transit Gateway → Project（Workload Network / Management Network，各掛 VPC Gateway）。

---

## Step 2 — Supervisor location

選 VPC 後，左側步驟列變 **7 步**（多了 Workload Network）。
兩個 tab：

- **VSPHERE ZONE DEPLOYMENT**：需要先設好 3 個 vSphere Zone（對應 3 cluster，做 zone 級 HA）。lab 沒設 → 顯示 "Setup vSphere Zones"。
- **CLUSTER DEPLOYMENT**（lab 用這個）：
  - **Supervisor name**：填 `vcf-m02-supervisor`
  - **Enable control plane high-availability** toggle
  - **Cluster selection**：左側樹 `kosten-vcf91-vc.rtolab.local → vcf-m02-dc`。
    **要先點 datacenter 節點 `vcf-m02-dc`**，右側 **COMPATIBLE** tab 才會列出 cluster。
  - 實機結果：**vcf-m02-cl01 → COMPATIBLE**，4 hosts、Available CPU 137.04 GHz、Available Memory 171.51 GB。
  - 提示：沒填 vSphere Zone name 會自動產生一個並指派給選的 cluster。

---

## Step 3 — Storage

三個 storage policy（都套用到 vcf-m02-cl01）：
- **Control Plane Storage Policy**
- **Ephemeral Disks Storage Policy**
- **Image Cache Storage Policy**

lab 三個都選 `Management Storage Policy - Single Node`（FTT=0）。

---

## Step 4 — Management Network（實機驗證欄位）

Supervisor 控制平面 VM 的管理網路：
- Network：選 VLAN 114 的 PG / segment
- Network Mode：Static
- Starting IP address：`192.168.114.101`（連續 5 個 .101–.105）
- Subnet mask：`255.255.255.0`
- Gateway：`192.168.114.254`
- DNS server：`192.168.114.200`；DNS search domain：`rtolab.local`
- NTP server：`192.168.114.200`

---

## Step 5 — Workload Network（VPC 模式關鍵步）

- **NSX Project**：`default`
- **VPC Connectivity Profile**：選 `vcf-m02-vks-vpc-profile`
  （本 repo Step1 已實際建好這個 profile；DTGW 路線它不綁 edge，Edge 路線它的 service_gateway 綁 edge cluster — UI 下拉看到的是同一個名字，差別在 profile 內容）
- Service CIDR (K8s ClusterIP)：`10.96.0.0/23`
- Default Private CIDR（namespace 子網來源）：`172.30.0.0/24`
- DNS / NTP：`192.168.114.200`

---

## Step 6 — Advanced Settings

- Content Library：指定 TKG subscribed library（訂閱 `https://wp-content.vmware.com/supervisor/v1/latest/lib.json`）
- Supervisor Control Plane Size：**Small**（lab）
- 其他（API server endpoint FQDN 等）視需要。

---

## Step 7 — Ready to complete

- 檢視所有設定 → **FINISH** 才正式部署（30–60 分鐘）。
- ⚠️ 本次實機**停在 wizard 中途、未按 FINISH**，沒有觸發部署。

---

## 截圖檔

實機截圖（Step intro / 1 / 2 / 3）已在對話中附給使用者；PNG 檔存在操作端 "RTO LAB" Chrome 的機器，
要放進 repo 的話把檔案丟進本資料夾即可（建議命名 `00-intro.png` / `01-vcenter-network.png` /
`02a-cluster-deploy.png` / `02b-cluster-compatible.png` / `03-storage.png`）。
