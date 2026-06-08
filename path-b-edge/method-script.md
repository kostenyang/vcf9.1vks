# Path B — Script 方法（PowerCLI + SDDC/NSX REST）

Edge cluster 部署有原生自動化（SDDC Manager API），是三條方法裡 script 支援最好的一條。

---

## 主力：SDDC Manager API

[`Step1-Deploy-Edge.ps1`](Step1-Deploy-Edge.ps1) 就是 script 方法：
- `POST /v1/edge-clusters/validations` 先驗證
- `POST /v1/edge-clusters` 正式部署（含 2 台 edge VM + T0 Active/Standby）
- 輪詢 task 到完成

```powershell
pwsh ./Step1-Deploy-Edge.ps1 -Validate     # 只驗證
pwsh ./Step1-Deploy-Edge.ps1 -DryRun       # 只印 payload
pwsh ./Step1-Deploy-Edge.ps1               # 正式部署
pwsh ./Step1b-Setup-Centralized-TGW.ps1    # 改 TGW centralized + VPC profile
```

---

## PowerCLI 角色：取值 + 驗證

```powershell
Connect-VIServer 192.168.114.11 -User administrator@vsphere.local -Password 'VMware1!VMware1!'
# edge 部署目標 cluster moref（SDDC API 用 cluster id，不是 moref，但驗證用）
Get-Cluster 'vcf-m02-cl01'
Get-Datastore | ? Name -match vsan
# 確認 overlay portgroup / VLAN 117 存在
Get-VDPortgroup | ? { $_.VlanConfiguration.VlanId -in 114,117 } | select Name,@{n='Vlan';e={$_.VlanConfiguration.VlanId}}
```

PowerCLI VCF 模組（`VCF.PowerCLI`）也有 edge cluster cmdlet：
```powershell
Install-Module VCF.PowerCLI
# 視版本可能有 New-VcfEdgeCluster / Get-VcfEdgeCluster 等（包裝 SDDC API）
Get-Command -Module VCF.* *edge*
```

---

## NSX Policy REST（centralized TGW）

PowerCLI/SDDC 不直接做「改 TGW 成 centralized + VPC profile 綁 edge」，這步走 NSX Policy REST：
[`Step1b-Setup-Centralized-TGW.ps1`](Step1b-Setup-Centralized-TGW.ps1)。

---

## 啟用 Supervisor

同 Path A：`Enable-WMCluster` 不支援 VPC 模式 → 用 REST
[`../common/Step2-Enable-Supervisor.ps1`](../common/Step2-Enable-Supervisor.ps1)。

---

## 方法支援度總表（Path B）

| 步驟 | API | UI | Script |
|------|-----|----|--------|
| 部 edge cluster + T0 | SDDC `/v1/edge-clusters` | guided wizard | SDDC API / VCF.PowerCLI |
| TGW centralized + VPC profile | NSX Policy REST | NSX Manager UI | NSX Policy REST |
| Enable Supervisor | vCenter REST | Activate Supervisor | REST（Enable-WMCluster 不支援 VPC）|
| 建 VKS cluster | kubectl | Namespaces UI | kubectl |
