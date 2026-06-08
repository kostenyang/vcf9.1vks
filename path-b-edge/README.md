# Path B — Edge + Centralized TGW

部 NSX Edge cluster + Tier-0，把 default TGW 改成 centralized（edge-based），
Supervisor LB/SNAT 由 Edge node 提供。

## 流程

```
../common/Step0-Check-Prereqs.ps1            # 確認沒有 edge cluster
Step1-Deploy-Edge.ps1   [API/SDDC]           # 部 edge cluster + T0 (Active/Standby)
  也可走 method-ui.md  [UI guided wizard]
  也可走 method-script.md [Script]
Step1b-Setup-Centralized-TGW.ps1 [API]       # TGW attachment + VPC profile 綁 edge
../common/Step2-Enable-Supervisor.ps1        # 啟用 Supervisor（指向 centralized profile）
../common/Step3-New-Namespace.ps1
../common/Step4-New-VksCluster.ps1
```

## 三種方法

| 方法 | 檔 |
|------|----|
| **API**（SDDC Manager `/v1/edge-clusters` + NSX Policy）| [`Step1-Deploy-Edge.ps1`](Step1-Deploy-Edge.ps1) + [`Step1b-Setup-Centralized-TGW.ps1`](Step1b-Setup-Centralized-TGW.ps1) |
| **UI**（vCenter guided Network Connectivity wizard）| [`method-ui.md`](method-ui.md) |
| **Script**（PowerCLI 取值 + REST）| [`method-script.md`](method-script.md) |

## 關鍵：Tier-0 必須 Active/Standby

VKS NAT 只在 T0 Active/Standby 下有效。本路線部 T0 一律設 `ACTIVE_STANDBY`。

## IP（取自 common/lab.ps1 + inventory）

| 用途 | 值 |
|------|----|
| Edge node mgmt | `192.168.114.70`, `.71` |
| Edge uplink | `192.168.114.72`, `.73` |
| Edge TEP | `192.168.117.28–.31`（VLAN 117 overlay）|
| Edge TEP VLAN | `117` |
| Uplink VLAN | `114` |
| T0 routing | STATIC（default route → `192.168.114.254`）|
| External IP block | `192.168.114.108/26` |
| Private TGW block | `172.30.0.0/16` |
| Supervisor CP | `192.168.114.101–105` |

## ⚠️ 注意

- Edge cluster 部署最久（含 OVA 部署 2 台 edge VM），約 30–60 分鐘。
- default project 的 TGW 只有一個；改成 centralized 前確認還沒有 active VPC（lab 乾淨，OK）。
- 若同時想保留 Path A（DTGW），Path B 建議**另開 NSX Project**避免 TGW 互斥。
