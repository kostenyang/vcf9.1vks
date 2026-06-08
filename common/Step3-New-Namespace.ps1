<#  Step3 — 建 VKS namespace（兩路線共用，REST API）
    建立 namespace $NS_NAME，設 storage policy + access list。 #>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"
Connect-Vc

$sup = (Vc-Get '/api/vcenter/namespace-management/supervisors') | Where-Object { $_.config_status -eq 'RUNNING' } | Select-Object -First 1
if (-not $sup) { Write-Host "✗ 沒有 RUNNING Supervisor，先跑 Step2。" -ForegroundColor Red; exit 1 }
Write-Host "Supervisor: $($sup.supervisor)"

try { $ex = Vc-Get "/api/vcenter/namespaces/instances/$NS_NAME"; Write-Host "✓ namespace '$NS_NAME' 已存在 ($($ex.config_status))，跳過。" -ForegroundColor Green; exit 0 } catch {}

$pols = Vc-Get '/rest/vcenter/storage/policies'
$pol  = ($pols.value | Where-Object { $_.name -match 'Single Node' } | Select-Object -First 1)
if (-not $pol) { $pol = $pols.value | Select-Object -First 1 }

$body = @{
    namespace  = $NS_NAME
    supervisor = $sup.supervisor
    storage_specs = @(@{ policy=$pol.policy; limit=204800 })
    access_list   = @(@{ subject_name='administrator'; subject_type='USER'; domain='vsphere.local'; role='EDIT' })
}
Vc-Post '/api/vcenter/namespaces/instances' $body | Out-Null
Write-Host "✓ namespace '$NS_NAME' 建立中" -ForegroundColor Green

$deadline=(Get-Date).AddMinutes(5)
do { Start-Sleep 15; $ns=Vc-Get "/api/vcenter/namespaces/instances/$NS_NAME"; Write-Host "  $($ns.config_status)"; if($ns.config_status -eq 'RUNNING'){break} } while((Get-Date) -lt $deadline)
Write-Host "namespace: $($ns.config_status)  → 下一步 Step4" -ForegroundColor Green
