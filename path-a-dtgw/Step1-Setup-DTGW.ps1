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

# 取部署 moref（PowerCLI）：cluster / datastore / mgmt DVPG
Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
Connect-VIServer -Server $VC -User $VCUSER -Password $VCPASS -Force | Out-Null
$clMoref = (Get-Cluster $CLUSTER_NAME).ExtensionData.MoRef.Value                                   # e.g. domain-c9
$dsMoref = (Get-Datastore | ? Name -match 'vsan' | Select -First 1).ExtensionData.MoRef.Value      # e.g. datastore-15
$pgMoref = (Get-VDPortgroup | ? { $_.VlanConfiguration.VlanId -eq 114 -and $_.Name -match 'pg-mgmt$' } | Select -First 1).Key  # e.g. dvportgroup-21
Disconnect-VIServer * -Confirm:$false -Force | Out-Null
Write-Host "  cluster=$clMoref  datastore=$dsMoref  mgmt_pg=$pgMoref"

# VNA cluster + node — schema 為實機部署後 GET 回來驗證的真實格式（非反推）
# ⚠️ form factor 必須 ≥ MEDIUM：官方要求啟用 vSphere Supervisor 的 VNA 最小是 Medium（Small 不支援）。
$vnaBase = "/policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters/$VNA_CLUSTER_ID"
$vnaCluster = @{
    resource_type         = 'VirtualNetworkApplianceCluster'
    display_name          = $VNA_CLUSTER_ID
    appliance_form_factor = 'MEDIUM'          # Supervisor 最小 Medium；Small 不支援
    appliance_type        = 'VirtualNetworkAppliance'
    service_type          = 'VPC_SERVICES'
}
Nsx-Patch -DryRun:$DryRun -path $vnaBase -body $vnaCluster | Out-Null

# VNA node — ip_assignment_specs 真實格式 = management_port_subnets + default_gateway + StaticIpv4
$vnaNode = @{
    resource_type = 'VirtualNetworkAppliance'
    id            = 'vcf-m02-vna01'
    display_name  = 'vcf-m02-vna01'
    hostname      = 'vcf-m02-vna01.rtolab.local'
    vm_deployment_config = @{
        compute_manager_id          = $cm.id            # f26a252e-...
        cluster_or_resource_pool_id = $clMoref          # domain-c9
        datastore_id                = $dsMoref          # datastore-15
        reservation_info = @{
            memory_reservation = @{ reservation_percentage = 100 }
            cpu_reservation    = @{ reservation_in_shares  = 'HIGH_PRIORITY' }
        }
    }
    management_interface = @{
        network_id = $pgMoref                           # dvportgroup-21（DVPG moref，非 NSX segment）
        ip_assignment_specs = @(@{
            ip_assignment_type      = 'StaticIpv4'
            management_port_subnets = @(@{ ip_addresses = @('192.168.114.106'); prefix_length = 24 })
            default_gateway         = @('192.168.114.254')
        })
    }
}
Nsx-Put -DryRun:$DryRun -path "$vnaBase/virtual-network-appliances/vcf-m02-vna01" -body $vnaNode | Out-Null
Write-Host "  ✓ VNA cluster (MEDIUM) + node" -ForegroundColor Green

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
