<#  Path A 補充 — per-VPC 開 Load Balancer（DTGW 用 VNA 提供 LB）
    Supervisor 啟用後，每個 namespace 對應一個 VPC；要 Service type=LoadBalancer 能用，
    需在該 VPC 開 LBService（UI 沒這 toggle，只能 API）。

    用法：pwsh ./enable-vpc-lb.ps1 -Vpc <vpc-id>   #>
param([Parameter(Mandatory)][string]$Vpc, [string]$LbId='default', [string]$Size='SMALL', [switch]$DryRun)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\common\lab.ps1"

Write-Host "列出 default project 下的 VPC（找 namespace 對應的那個）..." -ForegroundColor Cyan
(Nsx-Get "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpcs").results |
    Select-Object display_name,id | Format-Table -AutoSize | Out-String | Write-Host

$path = "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpcs/$Vpc/vpc-lbs/$LbId"
$body = @{ resource_type='LBService'; enabled=$true; size=$Size }
if ($DryRun) { Write-Host "[DryRun] PUT $path"; $body|ConvertTo-Json|Write-Host; exit 0 }
Nsx-Put -path $path -body $body | Out-Null
Write-Host "✓ VPC '$Vpc' LBService enabled (size=$Size)" -ForegroundColor Green
