<#  共用設定 + helper（其他 Step 腳本 dot-source 這支）
    用法：  . "$PSScriptRoot\..\common\lab.ps1"
#>

# ── Lab 連線 ──────────────────────────────────────────────────────────────────
$global:VC      = '192.168.114.11'              # inner vCenter (kosten-vcf91-vc)
$global:VCUSER  = 'administrator@vsphere.local'
$global:VCPASS  = 'VMware1!VMware1!'
$global:NSXVIP  = '192.168.114.13'              # NSX Manager VIP
$global:NSXUSER = 'admin'
$global:NSXPASS = 'VMware1!VMware1!'
$global:SDDC    = '192.168.114.10'              # SDDC Manager
$global:CLUSTER_NAME = 'vcf-m02-cl01'

# ── IP 規劃（見根目錄 README §IP）──────────────────────────────────────────
$global:SUP_NAME        = 'vcf-m02-supervisor'
$global:CP_START_IP     = '192.168.114.101'     # 5 consecutive: .101-.105
$global:CP_GATEWAY      = '192.168.114.254'
$global:CP_PREFIX       = 24
$global:DNS_SERVERS     = @('192.168.114.200')
$global:NTP_SERVERS     = @('192.168.114.200')
$global:DNS_SEARCH      = @('rtolab.local')
$global:SERVICE_CIDR    = '10.96.0.0'
$global:SERVICE_PREFIX  = 23

$global:EXT_IPBLOCK_CIDR = '192.168.114.128/26' # external (public/LB/SNAT); /26 必須對齊邊界 .0/.64/.128/.192
$global:PRIV_TGW_CIDR    = '172.30.0.0/16'      # private TGW block (VKS 要 /16)
$global:VPC_PRIVATE_CIDR = '172.30.0.0'
$global:VPC_PRIVATE_PREFIX = 24

# NSX 資源命名
$global:PROJECT_ID    = 'default'                       # 用 default project（lab 已有）
$global:EXT_IPBLOCK_ID = 'vcf-m02-vks-ext-ipblock'
$global:PRIV_TGW_ID    = 'vcf-m02-vks-priv-tgw'
$global:VPC_PROFILE_ID = 'vcf-m02-vks-vpc-profile'
$global:VNA_CLUSTER_ID = 'vcf-m02-vna-01'
$global:EDGE_CLUSTER_NAME = 'vcf-m02-edge-cl01'
$global:T0_NAME       = 'vcf-m02-t0'

# VKS namespace / cluster
$global:NS_NAME       = 'vks-automation'
$global:VKS_CLUSTER   = 'vks-auto-01'

# ── vCenter session helper ───────────────────────────────────────────────────
function Connect-Vc {
    $enc = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${VCUSER}:${VCPASS}"))
    $sid = Invoke-RestMethod -SkipCertificateCheck -Method Post -Uri "https://$VC/api/session" -Headers @{Authorization="Basic $enc"}
    $global:VCHDR = @{'vmware-api-session-id' = $sid}
}
function Vc-Get  { param($path) Invoke-RestMethod -SkipCertificateCheck -Uri "https://$VC$path" -Headers $VCHDR }
function Vc-Post { param($path,$body) Invoke-RestMethod -SkipCertificateCheck -Method Post -Uri "https://$VC$path" -Headers $VCHDR -Body ($body|ConvertTo-Json -Depth 20) -ContentType 'application/json' }

# ── NSX Policy helper ─────────────────────────────────────────────────────────
function Nsx-Hdr { @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${NSXUSER}:${NSXPASS}")); 'Content-Type'='application/json' } }
function Nsx-Get   { param($path) Invoke-RestMethod -SkipCertificateCheck -Uri "https://$NSXVIP$path" -Headers (Nsx-Hdr) }
function Nsx-Patch { param($path,$body,[switch]$DryRun)
    if ($DryRun) { Write-Host "  [DryRun] PATCH $path" -ForegroundColor DarkGray; ($body|ConvertTo-Json -Depth 20)|Write-Host; return }
    Invoke-RestMethod -SkipCertificateCheck -Method Patch -Uri "https://$NSXVIP$path" -Headers (Nsx-Hdr) -Body ($body|ConvertTo-Json -Depth 20)
}
function Nsx-Put { param($path,$body,[switch]$DryRun)
    if ($DryRun) { Write-Host "  [DryRun] PUT $path" -ForegroundColor DarkGray; ($body|ConvertTo-Json -Depth 20)|Write-Host; return }
    Invoke-RestMethod -SkipCertificateCheck -Method Put -Uri "https://$NSXVIP$path" -Headers (Nsx-Hdr) -Body ($body|ConvertTo-Json -Depth 20)
}

# ── SDDC Manager token ────────────────────────────────────────────────────────
function Get-SddcToken {
    $b = @{ username=$VCUSER; password=$VCPASS } | ConvertTo-Json
    (Invoke-RestMethod -SkipCertificateCheck -Method Post -Uri "https://$SDDC/v1/tokens" -Body $b -ContentType 'application/json').accessToken
}
