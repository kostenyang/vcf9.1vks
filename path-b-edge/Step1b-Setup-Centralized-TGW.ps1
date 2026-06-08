<#  Path B Step1b — 把 default TGW 改成 centralized + VPC profile 綁 edge（NSX Policy API）
    1. External IP Block (EXTERNAL) + Private TGW block (PRIVATE /16)
    2. TransitGatewayAttachment：connection_path 指向 T0（TGW SR 隨 T0 落在 edge）
    3. VPC Connectivity Profile：service_gateway.enable=true + edge_cluster_paths=[edge]

    前置：Step1-Deploy-Edge.ps1 已部好 edge cluster + T0。
    -DryRun  只印 payload 不送 #>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\lab.ps1"

# ── 找 T0 + edge cluster ─────────────────────────────────────────────────────
Write-Host "找 T0 + edge cluster..." -ForegroundColor Cyan
$t0 = (Nsx-Get '/policy/api/v1/infra/tier-0s').results | Where-Object { $_.display_name -match 'vcf-m02|t0' } | Select-Object -First 1
if (-not $t0) { $t0 = (Nsx-Get '/policy/api/v1/infra/tier-0s').results | Select-Object -First 1 }
if (-not $t0) { Write-Host "✗ 沒有 T0，先跑 Step1-Deploy-Edge.ps1" -ForegroundColor Red; exit 1 }
$ha = $t0.ha_mode
$c = if ($ha -eq 'ACTIVE_STANDBY'){'Green'}else{'Red'}
Write-Host "  T0: $($t0.display_name)  ha_mode=$ha  path=$($t0.path)" -ForegroundColor $c
if ($ha -ne 'ACTIVE_STANDBY') { Write-Host "  ⚠️ VKS NAT 需要 ACTIVE_STANDBY；繼續但啟用可能失敗。" -ForegroundColor Yellow }

$ec = (Nsx-Get '/policy/api/v1/infra/sites/default/enforcement-points/default/edge-clusters').results | Select-Object -First 1
if (-not $ec) { Write-Host "✗ 沒有 edge cluster，先跑 Step1-Deploy-Edge.ps1" -ForegroundColor Red; exit 1 }
Write-Host "  edge cluster: $($ec.display_name)  path=$($ec.path)"

# ── 1. IP blocks ─────────────────────────────────────────────────────────────
Write-Host "[1/3] IP blocks..." -ForegroundColor Cyan
Nsx-Patch -DryRun:$DryRun -path "/policy/api/v1/infra/ip-blocks/$EXT_IPBLOCK_ID" -body @{
    resource_type='IpAddressBlock'; display_name=$EXT_IPBLOCK_ID; cidr=$EXT_IPBLOCK_CIDR; visibility='EXTERNAL'
} | Out-Null
Nsx-Patch -DryRun:$DryRun -path "/policy/api/v1/infra/ip-blocks/$PRIV_TGW_ID" -body @{
    resource_type='IpAddressBlock'; display_name=$PRIV_TGW_ID; cidr=$PRIV_TGW_CIDR; visibility='PRIVATE'
} | Out-Null
Write-Host "  ✓ IP blocks" -ForegroundColor Green

# ── 2. TransitGatewayAttachment（接到 T0 = centralized）──────────────────────
Write-Host "[2/3] TransitGatewayAttachment → T0..." -ForegroundColor Cyan
$attBody = @{
    resource_type   = 'TransitGatewayAttachment'
    display_name    = 'vcf-m02-tgw-to-t0'
    connection_path = $t0.path
}
Nsx-Put -DryRun:$DryRun -path "/policy/api/v1/orgs/default/projects/$PROJECT_ID/transit-gateways/default/attachments/vcf-m02-tgw-to-t0" -body $attBody | Out-Null
Write-Host "  ✓ TGW attachment (centralized)" -ForegroundColor Green

# ── 3. VPC Connectivity Profile（綁 edge cluster）────────────────────────────
Write-Host "[3/3] VPC Connectivity Profile（centralized）..." -ForegroundColor Cyan
$profBody = @{
    resource_type        = 'VpcConnectivityProfile'
    display_name         = $VPC_PROFILE_ID
    transit_gateway_path = "/orgs/default/projects/$PROJECT_ID/transit-gateways/default"
    external_ip_blocks   = @("/infra/ip-blocks/$EXT_IPBLOCK_ID")
    private_tgw_ip_blocks= @("/infra/ip-blocks/$PRIV_TGW_ID")
    service_gateway      = @{
        enable             = $true
        edge_cluster_paths = @($ec.path)         # ← centralized 關鍵
    }
}
Nsx-Patch -DryRun:$DryRun -path "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpc-connectivity-profiles/$VPC_PROFILE_ID" -body $profBody | Out-Null
Write-Host "  ✓ VPC profile（centralized，綁 edge）" -ForegroundColor Green

Write-Host @"

=== Path B Step1b 完成 ===
  T0              : $($t0.path)  (ha=$ha)
  edge cluster    : $($ec.path)
  TGW attachment  : .../transit-gateways/default/attachments/vcf-m02-tgw-to-t0
  VPC profile     : .../vpc-connectivity-profiles/$VPC_PROFILE_ID  (service_gateway → edge)

下一步：
  pwsh ../common/Step2-Enable-Supervisor.ps1 -VpcProfileId $VPC_PROFILE_ID -DryRun
  pwsh ../common/Step2-Enable-Supervisor.ps1 -VpcProfileId $VPC_PROFILE_ID
"@ -ForegroundColor Green
