# Path A — DTGW + VNA

順應 lab 預設（default TGW 已是 DTGW），只需補 **VNA cluster** 給 Supervisor 提供 LB/SNAT。

## 流程

```
../common/Step0-Check-Prereqs.ps1        # 確認 DTGW 在、VNA 沒部
Step1-Setup-DTGW.ps1   [API]             # 建 external IP block + VNA cluster + 綁 VPC profile
  也可走 method-ui.md  [UI]
  也可走 method-script.md [Script/PowerCLI]
../common/Step2-Enable-Supervisor.ps1    # 啟用 Supervisor（指向 DTGW profile）
../common/Step3-New-Namespace.ps1
../common/Step4-New-VksCluster.ps1
```

## 三種方法

| 方法 | 檔 |
|------|----|
| **API**（REST，全自動）| [`Step1-Setup-DTGW.ps1`](Step1-Setup-DTGW.ps1) |
| **UI**（NSX Manager / vCenter 點選）| [`method-ui.md`](method-ui.md) |
| **Script**（PowerCLI + REST 混合）| [`method-script.md`](method-script.md) |

## 為什麼要 VNA

純 DTGW 跑在 host 上，給不了 stateful 服務。Supervisor 需要 LoadBalancer（kube-apiserver VIP +
Service type=LoadBalancer）和 SNAT（pod 連外）。VCF 9.1 的 **VNA cluster** 補上這些。
細節見 [../research/02-vna-research.md](../research/02-vna-research.md)。

## IP（取自 common/lab.ps1）

| 用途 | 值 |
|------|----|
| External IP block | `192.168.114.128/26` |
| Private TGW block | `172.30.0.0/16` |
| Supervisor CP | `192.168.114.101–105` |
| VNA cluster | `vcf-m02-vna-01`（SMALL，service_type=VPC_SERVICES）|

## ⚠️ 注意

- VNA create JSON 官方未公開；本腳本依 lab live OpenAPI schema 組（見 research/04）。**先 `-DryRun`**。
- VNA ≥2 節點才 HA。lab 先 1 台測通即可。
- 跑完 Supervisor 建好 namespace VPC 後，per-VPC 開 LB：見 [`enable-vpc-lb.ps1`](enable-vpc-lb.ps1)。
