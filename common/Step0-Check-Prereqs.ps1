<#  Step0 — 兩路線共用的前置檢查
    印出 NSX 版本、T0 HA mode、edge cluster、VNA cluster、default TGW span、
    VPC profile、Supervisor 狀態、cluster 相容性。
    根據結果決定走 Path A (DTGW) 還是 Path B (Edge)。 #>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"
Connect-Vc

Write-Host "`n=== NSX 版本 ===" -ForegroundColor Cyan
$v = Nsx-Get '/api/v1/node/version'
Write-Host "  NSX: $($v.product_version)"

Write-Host "`n=== T0 Gateways (VPC 需要 ACTIVE_STANDBY) ===" -ForegroundColor Cyan
$t0 = Nsx-Get '/policy/api/v1/infra/tier-0s'
if (-not $t0.results) { Write-Host "  (沒有 T0 — Path B 要先部 edge+T0)" -ForegroundColor Yellow }
foreach ($g in $t0.results) {
    $c = if ($g.ha_mode -eq 'ACTIVE_STANDBY') {'Green'} else {'Red'}
    Write-Host "  $($g.display_name)  ha_mode=$($g.ha_mode)  id=$($g.id)" -ForegroundColor $c
}

Write-Host "`n=== Edge clusters ===" -ForegroundColor Cyan
$ec = Nsx-Get '/policy/api/v1/infra/sites/default/enforcement-points/default/edge-clusters'
if (-not $ec.results) { Write-Host "  0 個 → Path B 要先部署 edge cluster" -ForegroundColor Yellow }
foreach ($e in $ec.results) { Write-Host "  $($e.display_name)  path=$($e.path)" }

Write-Host "`n=== VNA clusters ===" -ForegroundColor Cyan
$vna = Nsx-Get '/policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters'
if (-not $vna.results) { Write-Host "  0 個 → Path A 要先部署 VNA cluster" -ForegroundColor Yellow }
foreach ($n in $vna.results) { Write-Host "  $($n.display_name)  form=$($n.appliance_form_factor)  svc=$($n.service_type)" }

Write-Host "`n=== Default Transit Gateway (span) ===" -ForegroundColor Cyan
$tgw = Nsx-Get "/policy/api/v1/orgs/default/projects/$PROJECT_ID/transit-gateways/default"
Write-Host "  span.type=$($tgw.span.type)  transit_subnets=$($tgw.transit_subnets -join ',')  ext_signaling=$($tgw.external_ip_signaling_mode)"
if ($tgw.span.type -eq 'ClusterBasedSpan') { Write-Host "  → 目前是 DTGW（分散式）。Path A 直接用；Path B 要改 centralized。" -ForegroundColor Yellow }

Write-Host "`n=== VPC Connectivity Profiles ===" -ForegroundColor Cyan
$prof = Nsx-Get "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpc-connectivity-profiles"
foreach ($p in $prof.results) {
    $sg = if ($p.service_gateway.edge_cluster_paths) {"edge="+($p.service_gateway.edge_cluster_paths -join ',')} else {"(no edge / DTGW)"}
    Write-Host "  $($p.display_name)  default=$($p.is_default)  $sg"
}

Write-Host "`n=== External IP Blocks ===" -ForegroundColor Cyan
$ib = Nsx-Get '/policy/api/v1/infra/ip-blocks'
if (-not $ib.results) { Write-Host "  (無，Step1 會建)" -ForegroundColor Yellow }
foreach ($b in $ib.results) { Write-Host "  $($b.display_name)  cidr=$($b.cidr)  vis=$($b.visibility)" }

Write-Host "`n=== Supervisor 狀態 ===" -ForegroundColor Cyan
try {
    $sup = Vc-Get '/api/vcenter/namespace-management/supervisors'
    if (-not $sup) { Write-Host "  (尚未啟用 user Supervisor)" -ForegroundColor Yellow }
    foreach ($s in $sup) {
        $c = if ($s.config_status -eq 'RUNNING'){'Green'}else{'Yellow'}
        Write-Host "  $($s.supervisor)  status=$($s.config_status)  $($s.display_name)" -ForegroundColor $c
    }
} catch { Write-Host "  err: $($_.Exception.Message.Substring(0,80))" -ForegroundColor Yellow }

Write-Host "`n=== Cluster + 相容性 ===" -ForegroundColor Cyan
$cl = Vc-Get "/api/vcenter/cluster?names=$CLUSTER_NAME"
Write-Host "  cluster=$($cl[0].cluster)  name=$($cl[0].name)"

Write-Host "`n決策：" -ForegroundColor Green
Write-Host "  - 走 Path A (DTGW): cd path-a-dtgw; pwsh ./Step1-Setup-DTGW.ps1"
Write-Host "  - 走 Path B (Edge): cd path-b-edge; pwsh ./Step1-Deploy-Edge.ps1"
