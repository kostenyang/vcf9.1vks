<#  Path A Step1 — DTGW + VNA 設定（REST API）
    1. External IP Block（EXTERNAL）+ Private TGW IP Block（PRIVATE，/16）
    2. VNA cluster + 1 個 VNA 節點（VPC_SERVICES）
    3. 在 default project 的 VPC Connectivity Profile 綁 external block + private TGW block
       （DTGW 模式：service_gateway 不填 edge_cluster_paths）

    -DryRun  只印 payload 不送

    ⚠️ VNA create body 依 lab live OpenAPI schema（research/04）；建議先 -DryRun，
       或先 UI 部一台 VNA 再 GET 對照欄位。 #>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\lab.ps1"
Connect-Vc

# ── 1. External + Private IP blocks ──────────────────────────────────────────
Write-Host "[1/3] External IP Block ($EXT_IPBLOCK_CIDR) + Private TGW block ($PRIV_TGW_CIDR)..." -ForegroundColor Cyan
Nsx-Patch -DryRun:$DryRun -path "/policy/api/v1/infra/ip-blocks/$EXT_IPBLOCK_ID" -body @{
    resource_type='IpAddressBlock'; display_name=$EXT_IPBLOCK_ID; cidr=$EXT_IPBLOCK_CIDR; visibility='EXTERNAL'
} | Out-Null
Nsx-Patch -DryRun:$DryRun -path "/policy/api/v1/infra/ip-blocks/$PRIV_TGW_ID" -body @{
    resource_type='IpAddressBlock'; display_name=$PRIV_TGW_ID; cidr=$PRIV_TGW_CIDR; visibility='PRIVATE'
} | Out-Null
Write-Host "  ✓ IP blocks" -ForegroundColor Green

# ── 2. VNA cluster + node ────────────────────────────────────────────────────
Write-Host "[2/3] VNA cluster '$VNA_CLUSTER_ID' + node..." -ForegroundColor Cyan

# 取 compute manager id (vCenter)
$cmList = Nsx-Get '/api/v1/fabric/compute-managers'
$cm = $cmList.results | Where-Object { $_.server -eq $VC -or $_.display_name -match 'vcf-m02|kosten' } | Select-Object -First 1
if (-not $cm) { $cm = $cmList.results | Select-Object -First 1 }
Write-Host "  compute manager: $($cm.display_name)  id=$($cm.id)"

# 取 overlay transport zone
$tz = (Nsx-Get '/policy/api/v1/infra/sites/default/enforcement-points/default/transport-zones').results | Where-Object { $_.tz_type -match 'OVERLAY' } | Select-Object -First 1
Write-Host "  overlay TZ: $($tz.display_name)  path=$($tz.path)"

# VNA cluster（先建空 cluster，再 PUT node 為 child）
$vnaCluster = @{
    resource_type        = 'VirtualNetworkApplianceCluster'
    display_name         = $VNA_CLUSTER_ID
    appliance_form_factor= 'SMALL'
    appliance_type       = 'VirtualNetworkAppliance'
    service_type         = 'VPC_SERVICES'
    advanced_configuration = @{ overlay_transport_zone_path = $tz.path }
}
$vnaBase = "/policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters/$VNA_CLUSTER_ID"
Nsx-Patch -DryRun:$DryRun -path $vnaBase -body $vnaCluster | Out-Null

# VNA node（cluster child）
# 注意：cluster_or_resource_pool_id / datastore_id 需用 NSX 認得的 moref；
#       下面用 placeholder，DryRun 會印出，正式跑前填實際值（見 method-ui.md 取得方式）。
$vnaNode = @{
    resource_type = 'VirtualNetworkAppliance'
    display_name  = 'vcf-m02-vna01'
    hostname      = 'vcf-m02-vna01.rtolab.local'
    vm_deployment_config = @{
        compute_manager_id          = $cm.id
        cluster_or_resource_pool_id = '<CLUSTER_OR_RP_MOREF>'   # ← 填 vcf-m02-cl01 的 moref
        datastore_id                = '<DATASTORE_MOREF>'        # ← 填 vSAN datastore moref
    }
    management_interface = @{
        network_id = '<MGMT_PORTGROUP_ID>'                       # ← VLAN114 PG / segment id
        ip_assignment_specs = @(@{
            resource_type='StaticIpPoolSpec'   # 或 StaticIpListSpec / DhcpAddressSpec
            # 視 schema 細節，UI 部一台後 GET 對照最準
        })
    }
    credentials = @{ cli_password=$NSXPASS; root_password=$NSXPASS; audit_password=$NSXPASS; cli_username='admin'; audit_username='audit' }
}
Nsx-Put -DryRun:$DryRun -path "$vnaBase/virtual-network-appliances/vcf-m02-vna01" -body $vnaNode | Out-Null
Write-Host "  ✓ VNA cluster + node（DryRun 請檢視 placeholder moref 是否需填）" -ForegroundColor Green

# ── 3. VPC Connectivity Profile（DTGW：不綁 edge）─────────────────────────────
Write-Host "[3/3] VPC Connectivity Profile '$VPC_PROFILE_ID'（DTGW 模式）..." -ForegroundColor Cyan
$tgwPath = "/orgs/default/projects/$PROJECT_ID/transit-gateways/default"
$profBody = @{
    resource_type        = 'VpcConnectivityProfile'
    display_name         = $VPC_PROFILE_ID
    transit_gateway_path = $tgwPath
    external_ip_blocks   = @("/infra/ip-blocks/$EXT_IPBLOCK_ID")
    private_tgw_ip_blocks= @("/infra/ip-blocks/$PRIV_TGW_ID")
    # DTGW: service_gateway 不填 edge_cluster_paths（stateful 走 VNA + distributed VLAN connection）
}
Nsx-Patch -DryRun:$DryRun -path "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpc-connectivity-profiles/$VPC_PROFILE_ID" -body $profBody | Out-Null
Write-Host "  ✓ VPC profile（DTGW）" -ForegroundColor Green

Write-Host @"

=== Path A Step1 完成 ===
  external block : /infra/ip-blocks/$EXT_IPBLOCK_ID
  private tgw    : /infra/ip-blocks/$PRIV_TGW_ID
  VNA cluster    : $vnaBase
  VPC profile    : /orgs/default/projects/$PROJECT_ID/vpc-connectivity-profiles/$VPC_PROFILE_ID

下一步：
  pwsh ../common/Step2-Enable-Supervisor.ps1 -VpcProfileId $VPC_PROFILE_ID -DryRun   # 先檢視
  pwsh ../common/Step2-Enable-Supervisor.ps1 -VpcProfileId $VPC_PROFILE_ID           # 正式啟用

⚠️ 若 VNA node 有 placeholder moref，先依 method-ui.md 取得實際 moref 再正式跑，
   或直接用 UI 部 VNA（method-ui.md），其餘步驟仍可用本腳本。
"@ -ForegroundColor Green
