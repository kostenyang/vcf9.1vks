#!/usr/bin/env python3
"""
Step1 (Path A / DTGW) — NSX IP blocks + VPC Connectivity Profile（對應 Step1-Setup-DTGW.ps1）。

  python step1_setup_dtgw.py [--dry-run]

本腳本做「純 NSX Policy API」可做的部分：
  1. External IP Block（EXTERNAL）+ Private TGW IP Block（PRIVATE，/16）
  2. default project 的 VPC Connectivity Profile（綁 external + private TGW block）

⚠️ VNA cluster + 節點部署需要 compute moref（cluster/datastore/mgmt DVPG）+ 靜態 IP，
   moref 要從 vCenter 撈，建議用 UI（path-a-dtgw/method-ui.md）或 PowerShell Step1 部 VNA，
   其餘步驟本腳本可用。VNA path 要放進 profile 的 service_gateway.edge_cluster_paths（見 method-ui）。
"""
import sys
import lab


def main():
    dry = "--dry-run" in sys.argv
    nsx = lab.Nsx()

    # 1. External + Private IP blocks ------------------------------------------
    print(f"[1/2] External IP Block ({lab.EXT_IPBLOCK_CIDR}) + Private TGW block ({lab.PRIV_TGW_CIDR})...")
    nsx.patch(f"/policy/api/v1/infra/ip-blocks/{lab.EXT_IPBLOCK_ID}", {
        "resource_type": "IpAddressBlock", "display_name": lab.EXT_IPBLOCK_ID,
        "cidr": lab.EXT_IPBLOCK_CIDR, "visibility": "EXTERNAL",
    }, dry_run=dry)
    nsx.patch(f"/policy/api/v1/infra/ip-blocks/{lab.PRIV_TGW_ID}", {
        "resource_type": "IpAddressBlock", "display_name": lab.PRIV_TGW_ID,
        "cidr": lab.PRIV_TGW_CIDR, "visibility": "PRIVATE",
    }, dry_run=dry)
    print("  ✓ IP blocks")

    # 2. VPC Connectivity Profile（DTGW：不綁 edge）-----------------------------
    print(f"[2/2] VPC Connectivity Profile '{lab.VPC_PROFILE_ID}'（DTGW 模式）...")
    prof = {
        "resource_type": "VpcConnectivityProfile",
        "display_name": lab.VPC_PROFILE_ID,
        "transit_gateway_path": f"/orgs/default/projects/{lab.PROJECT_ID}/transit-gateways/default",
        "external_ip_blocks": [f"/infra/ip-blocks/{lab.EXT_IPBLOCK_ID}"],
        "private_tgw_ip_blocks": [f"/infra/ip-blocks/{lab.PRIV_TGW_ID}"],
        # DTGW: service_gateway.edge_cluster_paths 要放 VNA cluster path（VNA 部好後補）：
        #   /infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters/<id>
        # 加上 nat_config.enable_default_snat=True 才有對外 SNAT。
    }
    nsx.patch(
        f"/policy/api/v1/orgs/default/projects/{lab.PROJECT_ID}/vpc-connectivity-profiles/{lab.VPC_PROFILE_ID}",
        prof, dry_run=dry)
    print("  ✓ VPC profile（DTGW）")

    print(f"""
=== Step1 (DTGW) 完成 ===
  external block : /infra/ip-blocks/{lab.EXT_IPBLOCK_ID}
  private tgw    : /infra/ip-blocks/{lab.PRIV_TGW_ID}
  VPC profile    : /orgs/default/projects/{lab.PROJECT_ID}/vpc-connectivity-profiles/{lab.VPC_PROFILE_ID}

下一步：部 VNA（UI/PowerShell）→ 把 VNA path + nat 補進 profile 的 service_gateway
        → 建 DistributedVlanConnection + TransitGatewayAttachment（見 research/04）
        → python step2_enable_supervisor.py
""")


if __name__ == "__main__":
    main()
