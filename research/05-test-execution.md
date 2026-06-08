# 05 — 實測執行紀錄（2026-06-08）

實際對 lab live API 跑過的結果（不是只有研究，是真的送/驗過）。

---

## DryRun（兩路線 payload 驗證，零風險）

### Path A — `Step1-Setup-DTGW.ps1 -DryRun`
- live 撈到 compute manager id = `f26a252e-1896-4788-94e4-e506c853104c`（kosten-vcf91-vc）
- live 撈到 overlay TZ = `nsx-overlay-transportzone`（`/infra/sites/default/enforcement-points/default/transport-zones/1b3a2f36-...`）
- 印出 external/private IP block、VNA cluster、VNA node、VPC profile 的 payload。
- VNA node 的 `cluster_or_resource_pool_id` / `datastore_id` / `network_id` 仍是 placeholder（要實際部 VM 才需填，見下方）。

### Path B — `Step1-Deploy-Edge.ps1 -DryRun`
- SDDC Manager token OK
- live 撈到 domain `vcf-m02` id=`047443ee-ae84-4b37-a2e3-8ca1a8f64144`
- live 撈到 cluster `vcf-m02-cl01` id=`65d2cc83-f61a-4042-a55c-d3528ad0e125`
- 印出 `POST /v1/edge-clusters` 完整 spec（2 台 MEDIUM edge、T0 ACTIVE_STANDBY、TEP VLAN 117、uplink VLAN 114）。

---

## 實際建立（低風險、可刪 — 已 PATCH 成功）

| 資源 | 值 | 狀態 |
|------|----|------|
| External IP Block | `vcf-m02-vks-ext-ipblock` = `192.168.114.128/26` (EXTERNAL) | ✅ 已建 |
| Private TGW Block | `vcf-m02-vks-priv-tgw` = `172.30.0.0/16` (PRIVATE) | ✅ 已建 |
| DTGW VPC Connectivity Profile | `vcf-m02-vks-vpc-profile`（ext + priv block，無 edge）| ✅ 已建 |

→ 這些讓 vCenter Supervisor wizard 的 Networking 步驟選得到 `vcf-m02-vks-vpc-profile`。

---

## 🐞 實測抓到的真 bug：external IP block /26 邊界

第一次用 `192.168.114.108/26` 被 NSX 退：

```
httpStatus: BAD_REQUEST  error_code: 520001
"Invalid CIDR 192.168.114.108/26 ... Network address should match corresponding prefix length."
```

**原因**：`/26` 的網段位址必須對齊 /26 邊界（`.0` / `.64` / `.128` / `.192`），`.108` 不是邊界。
**修正**：改 `192.168.114.128/26`（.128–.191，lab 內未用），通過。
→ 已回寫 `common/lab.ps1` 與所有文件。

> 教訓：external IP block 的 CIDR 一定要對齊 prefix 邊界；private TGW block `172.30.0.0/16` 本來就對齊所以沒事。

---

## Content Library（已建好，實測踩到 thumbprint 坑）

- 目標：subscribed library 訂 `https://wp-content.vmware.com/supervisor/v1/latest/lib.json`（Supervisor image 來源）。
- **第一次 API 失敗**：`RESOURCE_INACCESSIBLE / Connection to VCSP server failed` —— 誤判成 egress 不通。
- **真因**：REST API 建 subscribed library **沒帶 `ssl_thumbprint`**，vCenter 無法驗證對方憑證。
  UI 流程會跳「Security Alert」憑證信任視窗（按 Yes 即過）證明 **egress 其實是通的**。
- **修正**：腳本自動抓 SSL thumbprint（實測 `B6:49:37:52:8A:...`）塞進 spec → 成功。
- 結果：`tkg-content-library`（SUBSCRIBED）sync 後 **7 個 item**
  （`supervisor-9.0.0`/`9.0.2` OVF、`spherelet-v1.28`～`v1.32`）。
- 兩種方法都驗過：UI（5 步 wizard，按 YES 信任憑證）、Script（`Step1b-Create-ContentLibrary.ps1`，自動 thumbprint）。

詳見 [../common/content-library.md](../common/content-library.md)。

## VNA cluster 部署（DTGW 路線）— 實測 + 一個關鍵坑

- **UI 部署**：NSX Manager `System → Fabric → VNA Clusters → ADD CLUSTER` → node（compute manager/cluster/datastore/mgmt 下拉自動帶 moref）→ SAVE。
- **🐞 form factor 坑（你提醒抓到的）**：先選了 **Small** → 官方明文
  「The Medium form factor is the smallest size if you plan on enabling vSphere Supervisor」
  → **Small 不支援 Supervisor**，砍掉重部 **Medium**。
- **刪除留 orphaned VM**：in-progress 時刪 VNA cluster，NSX 移除 cluster 物件但**留下半部署的 VM**（PoweredOff），要手動 `Remove-VM` 清掉才能同名重建。
- **真實 node schema（部署後 GET 回來，補完 API 方法）**：
  ```
  vm_deployment_config: { compute_manager_id, cluster_or_resource_pool_id=domain-c9,
    datastore_id=datastore-15, reservation_info:{memory 100%, cpu HIGH_PRIORITY} }
  management_interface:
    network_id = dvportgroup-21          ← DVPG moref（不是 NSX segment）
    ip_assignment_specs = [{ ip_assignment_type: StaticIpv4,
      management_port_subnets:[{ip_addresses:[192.168.114.106], prefix_length:24}],
      default_gateway:[192.168.114.254] }]
  ```
  （原本反推用 StaticIpPoolSpec 是錯的；已回寫 `Step1-Setup-DTGW.ps1`。）
- **API 方法驗證**：用修正後的 `Step1-Setup-DTGW.ps1` 重建 Medium 成功 → API 方法端到端可用。
- 現狀：`vcf-m02-vna-01`（MEDIUM, VPC_SERVICES）部署中。

## 尚未執行（重部署，等決定）

| 動作 | 原因 |
|------|------|
| VNA cluster 實際部署（Path A）| 會部 VM、要填 cluster/datastore/PG moref + IP；建議 UI 部一台再 GET 對照，或補齊 moref 後跑 Step1 |
| Edge cluster 實際部署（Path B）| 部 2 台 edge VM、30–60 分鐘、吃 nested 資源；且與 Path A 共用 default project TGW（互斥）|
| Supervisor 啟用（Step2）| 等上面網路就緒 + TKG content library 後 |

> 兩條重部署互斥（同一個 default project 只有一個 TGW）。要兩條都實測，建議：
> 先完整跑 A → 截圖/驗證 → 清掉 → 再跑 B；或 Path B 另開 NSX Project。
