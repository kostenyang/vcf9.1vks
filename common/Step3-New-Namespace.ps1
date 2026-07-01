<#  Step3 — 建 VKS namespace（兩路線共用，REST API）
    建立 namespace $NS_NAME，設 storage policy + access list。 #>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"
Connect-Vc

# 注意：GET /supervisors 在 9.1 回 404，要用 /supervisors/summaries（items[].supervisor / items[].info.config_status）
$sum = (Vc-Get '/api/vcenter/namespace-management/supervisors/summaries').items | Where-Object { $_.info.config_status -eq 'RUNNING' } | Select-Object -First 1
if (-not $sum) { Write-Host "✗ 沒有 RUNNING Supervisor，先跑 Step2。" -ForegroundColor Red; exit 1 }
$supId = $sum.supervisor
Write-Host "Supervisor: $supId  ($($sum.info.name) @ $($sum.info.APIEndpoint))"

try { $ex = Vc-Get "/api/vcenter/namespaces/instances/$NS_NAME"; Write-Host "✓ namespace '$NS_NAME' 已存在 ($($ex.config_status))，跳過。" -ForegroundColor Green; exit 0 } catch {}

$pols = Vc-Get '/rest/vcenter/storage/policies'
$pol  = ($pols.value | Where-Object { $_.name -match 'Single Node' } | Select-Object -First 1)
if (-not $pol) { $pol = $pols.value | Select-Object -First 1 }

# v1 namespaces instances create_spec 用 'cluster'(ClusterComputeResource moref),非 'supervisor'
$clusterMoref = (Vc-Get '/api/vcenter/cluster').value | Where-Object { $_.name -eq 'vcf-m02-cl01' } | Select-Object -First 1 -ExpandProperty cluster
if (-not $clusterMoref) { $clusterMoref = 'domain-c9' }
$body = @{
    namespace  = $NS_NAME
    cluster    = $clusterMoref
    storage_specs = @(@{ policy=$pol.policy; limit=204800 })
    access_list   = @(@{ subject='administrator'; subject_type='USER'; domain='vsphere.local'; role='EDIT' })
}
Vc-Post '/api/vcenter/namespaces/instances' $body | Out-Null
Write-Host "✓ namespace '$NS_NAME' 建立中" -ForegroundColor Green

$deadline=(Get-Date).AddMinutes(5)
do { Start-Sleep 15; $ns=Vc-Get "/api/vcenter/namespaces/instances/$NS_NAME"; Write-Host "  $($ns.config_status)"; if($ns.config_status -eq 'RUNNING'){break} } while((Get-Date) -lt $deadline)
Write-Host "namespace: $($ns.config_status)  → 下一步 Step4" -ForegroundColor Green
