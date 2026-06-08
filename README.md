# vcf9.1vks — 在 VCF 9.1 (rtolab) 起 VKS 給 Automation 用

研究 + 自動化腳本：在 **VMware Cloud Foundation 9.1** 的 management domain
(`kosten-vcf91-vc.rtolab.local`) 上啟用 **vSphere Supervisor / VKS (vSphere Kubernetes Service)**，
給 automation 建立可用的 Kubernetes cluster。

兩條網路路線、每條三種方法（API / UI / Script）都涵蓋。

> ⚠️ 本 repo 為私有 lab 用途，內含明文 lab 密碼（`VMware1!VMware1!`）。正式環境請改掉。

---

## TL;DR — 兩條路線

VCF 9.1 的 NSX VPC 網路有兩種 Transit Gateway 連線模型，VKS Supervisor 都能用：

| | **Path A — DTGW + VNA** | **Path B — Edge + Centralized TGW** |
|---|---|---|
| Transit Gateway span | Distributed（跑在 ESXi host 上）| Centralized（跑在 NSX Edge VM 上）|
| 需要 NSX Edge cluster | ❌ 不需要 | ✅ 需要（2× MEDIUM edge VM）|
| stateful 服務（SNAT/LB）| 靠 **VNA cluster**（9.1 新功能）| 靠 Edge node |
| lab 現狀 | default TGW 已是 DTGW，**只缺 VNA** | edge cluster **還沒部署** |
| 部署成本 | 部 1 個 VNA cluster | 部 edge cluster + 改 TGW span |
| 適合 | 測 9.1 新架構、host 資源夠 | 傳統成熟路線、要 BGP/ECMP |
| 對應目錄 | [`path-a-dtgw/`](path-a-dtgw/) | [`path-b-edge/`](path-b-edge/) |

兩條路線共用的步驟（檢查、啟用 Supervisor、建 namespace、建 VKS cluster）放在 [`common/`](common/)。

---

## Lab NSX 實況（2026-06-08 探測，見 [research/00](research/00-lab-nsx-current-state.md)）

| 項目 | 狀態 |
|---|---|
| NSX 版本 | **9.1.0.0.25318225** |
| inner vCenter | `192.168.114.11` (`kosten-vcf91-vc.rtolab.local`) |
| NSX Manager VIP | `192.168.114.13` |
| Default Transit Gateway | 存在，`ClusterBasedSpan` = **DTGW**，transit subnet `100.64.0.0/21` |
| Default VPC Connectivity Profile | 存在，指向 default DTGW |
| NSX Edge cluster | **0 個**（inventory 寫的 `vcf-m02-edge-cl01` 其實沒部）|
| VNA cluster | **0 個**（feature 在，未部署）|
| VCFA 內部 VSP | `.19` VIP / `.20-.23` nodes（**不要動**，跟 user VKS 無關）|

---

## IP 規劃（rtolab `192.168.114.0/24`）

### 已佔用（節選，完整見 [research/00](research/00-lab-nsx-current-state.md)）
`.5` installer · `.10` SDDC · `.11` vC · `.12-.13` NSX · `.14-.17` ESXi ·
`.19-.23` VCFA VSP（勿動）· `.75-.87` Ops/Automation/Lic/vIDB · `.200` AD/DNS · `.254` GW

### VKS 新增

| 用途 | 值 | 兩路線通用? |
|------|----|-----------|
| Supervisor CP VMs (5 IPs) | `192.168.114.101–105` | ✅ |
| Supervisor mgmt gateway | `192.168.114.254` | ✅ |
| NSX External IP Block（public/LB/SNAT 來源）| `192.168.114.128/26`（.128–.191）| ✅ |
| Private TGW IP Block（VKS 要求 /16）| `172.30.0.0/16` | ✅ |
| Supervisor Service CIDR (K8s ClusterIP) | `10.96.0.0/23` | ✅ |
| VKS cluster Pod CIDR（per cluster）| `192.168.0.0/16` | ✅ |
| VKS cluster Service CIDR（per cluster）| `10.96.0.0/12` | ✅ |
| Edge TEP（Path B 才需要）| `192.168.117.x`（overlay VLAN 117）| Path B |
| Edge uplink（Path B 才需要）| `192.168.114.72–.73`（inventory 規劃）| Path B |

> **/16 私有 TGW block 是硬規定**：VCF 9.1 的 VKS 要求 private transit gateway IP block 是 `/16`。
> **衝突確認**：VCFA internal cluster CIDR = `172.27.0.0/16`，本規劃用 `172.30.0.0/16`，無重疊。

---

## 執行流程

```
                      ┌─ common/Step0-Check-Prereqs.ps1  （兩路線都先跑）
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
  Path A (DTGW)                Path B (Edge)
  path-a-dtgw/                 path-b-edge/
   Step1  建 VNA + VPC profile   Step1  部 Edge cluster
   (API/UI/Script)              Step1b 改 TGW 成 centralized + VPC profile
                                (API/UI/Script)
        └─────────────┬─────────────┘
                      ▼
   common/Step2-Enable-Supervisor.ps1   （API / PowerCLI；UI 見各 path README）
   common/Step3-New-Namespace.ps1
   common/Step4-New-VksCluster.ps1      （kubectl + ClusterClass）
                      ▼
            kubeconfig → 給 automation 用
```

---

## 三種方法對照

| 方法 | 在哪 | 說明 |
|------|------|------|
| **API** | `Step*.ps1`（REST）+ `path-*/method-api.md` | NSX Policy API + vCenter namespace-management API，純 REST，可完全自動化 |
| **UI** | `path-*/method-ui.md` | NSX Manager / vCenter 點選步驟，含每個欄位填什麼 |
| **Script** | `Step*-PowerCLI.ps1` + `path-*/method-script.md` | PowerCLI cmdlet（`Enable-WMCluster` 等）+ SDDC Manager API |

---

## 研究過程文件

| 檔 | 內容 |
|---|------|
| [research/00-lab-nsx-current-state.md](research/00-lab-nsx-current-state.md) | lab NSX live 探測結果（API 回傳原文）|
| [research/01-dtgw-vs-edge.md](research/01-dtgw-vs-edge.md) | DTGW vs Centralized TGW 架構比較 |
| [research/02-vna-research.md](research/02-vna-research.md) | VNA cluster 部署研究（含 live OpenAPI schema）|
| [research/03-edge-ctgw-research.md](research/03-edge-ctgw-research.md) | Edge cluster + centralized TGW 研究 |
| [research/04-nsx-schemas.md](research/04-nsx-schemas.md) | 從 NSX 9.1 live OpenAPI 撈的真實 schema 參考 |
| [research/05-test-execution.md](research/05-test-execution.md) | 實測執行紀錄：DryRun、已建資源、抓到的 /26 邊界 bug |

---

## ⚠️ 已知不確定處（誠實標註）

官方**沒有公開** VNA cluster create 的 JSON body，也沒公開 9.1 `POST .../supervisors` 的 VPC-mode 完整 body。
本 repo 的 schema 是從 **lab 自己的 NSX 9.1 live OpenAPI spec** (`/policy/api/v1/spec/openapi/nsx_policy_api.json`) 撈出來的真實欄位，
但實際送出前建議：

1. VNA / Supervisor 先用 **UI 各做一次**，再 `GET` 回來對照欄位（最保險）。
2. 或 dry-run 模式先驗證 payload，再正式送。

所有 `Step*.ps1` 都支援 `-DryRun`（印 payload 不送出）。
