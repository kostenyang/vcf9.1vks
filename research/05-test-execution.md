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

## 尚未執行（重部署，等決定）

| 動作 | 原因 |
|------|------|
| VNA cluster 實際部署（Path A）| 會部 VM、要填 cluster/datastore/PG moref + IP；建議 UI 部一台再 GET 對照，或補齊 moref 後跑 Step1 |
| Edge cluster 實際部署（Path B）| 部 2 台 edge VM、30–60 分鐘、吃 nested 資源；且與 Path A 共用 default project TGW（互斥）|
| Supervisor 啟用（Step2）| 等上面網路就緒 + TKG content library 後 |

> 兩條重部署互斥（同一個 default project 只有一個 TGW）。要兩條都實測，建議：
> 先完整跑 A → 截圖/驗證 → 清掉 → 再跑 B；或 Path B 另開 NSX Project。
