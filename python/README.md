# Python 方法 — 起 VKS

對應 PowerShell（`common/Step*.ps1`、`path-a-dtgw/Step1-Setup-DTGW.ps1`）的 Python 版，
給「拿去做開發」用。純 `requests` 打 vCenter / NSX REST，VKS cluster 用 kubectl 或 kubernetes client。

## 安裝
```bash
pip install -r requirements.txt
```

## 設定
連線參數在 `lab.py`，預設值 = 本 lab（2026-06-08 實機）。可用環境變數覆寫：
```bash
export VC=192.168.114.11 VCUSER=administrator@vsphere.local VCPASS='VMware1!VMware1!'
export NSXVIP=192.168.114.13 NSXUSER=admin NSXPASS='VMware1!VMware1!'
```

## 流程（DTGW 路線）
| 步驟 | 腳本 | 做什麼 | API |
|------|------|--------|-----|
| 1 | `step1_setup_dtgw.py` | NSX external/private IP block + VPC connectivity profile | NSX Policy `PATCH /policy/api/v1/...` |
| (VNA) | — | VNA cluster + 節點（要 compute moref）→ 用 UI 或 PowerShell；VNA path 補進 profile | NSX Policy |
| 2 | `step2_enable_supervisor.py` | 啟用 Supervisor（VPC mode）| vCenter `POST /api/vcenter/namespace-management/supervisors` |
| 3 | `step3_new_namespace.py` | 建 namespace（storage policy + access）| vCenter `POST /api/vcenter/namespaces/instances` |
| 4 | `step4_new_vks_cluster.py` | 建 VKS guest cluster（Cluster CR）| Supervisor kube API（kubectl / kubernetes client）|

```bash
python step1_setup_dtgw.py --dry-run     # 先看 payload
python step1_setup_dtgw.py
# （部 VNA：見 ../path-a-dtgw/method-ui.md）
python step2_enable_supervisor.py --dry-run
python step2_enable_supervisor.py
python step3_new_namespace.py
# 先登入 Supervisor 產生 kubeconfig context：
#   kubectl-vsphere login --server=192.168.114.132 -u administrator@vsphere.local --insecure-skip-tls-verify
python step4_new_vks_cluster.py          # 或 --client 用 kubernetes python client
```

## 內建的兩個實測修正
- **pod CIDR**：不可用預設 `192.168.0.0/16`（撞管理網段 `192.168.114.0/24` → CP 連不到 DNS/registry/Supervisor）→ 用 `100.96.0.0/11`。
- **MHC**：nested 慢，CP bootstrap 可能 >60min；直接 patch MHC 被 RBAC 擋，改用 `topology.controlPlane.healthCheck` 把 `nodeStartupTimeoutSeconds` 拉到 4h。

> 四種方法對照：UI（`../path-a-dtgw/method-ui.md` + `../screenshots/`）、PowerShell（`../common/Step*.ps1`）、
> API（raw REST，見 `../API.md`）、Python（本目錄）。
