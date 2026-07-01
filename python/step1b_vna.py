#!/usr/bin/env python3
"""
Step1b — 部署 VNA cluster + node，更新 VPC profile，建 DVC + TGW attachment。

在 step1_setup_dtgw.py 之後、step2_enable_supervisor.py 之前執行。

  python step1b_vna.py [--dry-run]

步驟（照順序）：
  1. VNA cluster (MEDIUM, VPC_SERVICES)
  2. VNA node (192.168.114.106)
  3. 等 VNA cluster.members 非空（node 就緒，最多 30 分鐘）
  4. 更新 VPC profile → service_gateway { VNA + SNAT }
  5. DistributedVlanConnection (VLAN 114, gw 192.168.114.254/24)
  6. TransitGatewayAttachment (default TGW → DVC)

morefs（research/05 實測確認）：
  compute_manager = f26a252e-1896-4788-94e4-e506c853104c
  cluster moref   = domain-c9
  datastore moref = datastore-15
  mgmt DVPG moref = dvportgroup-21
"""
import sys
import time
import lab

VNA_BASE_PATH = (
    f"/policy/api/v1/infra/sites/default/enforcement-points/default"
    f"/virtual-network-appliance-clusters/{lab.VNA_CLUSTER_ID}"
)
VNA_NODE_PATH = f"{VNA_BASE_PATH}/virtual-network-appliances/vcf-m02-vna01"

# Morefs from research/05 (confirmed 2026-06-08, stable lab hardware)
CM_ID       = "f26a252e-1896-4788-94e4-e506c853104c"   # compute manager (vCenter)
CL_MOREF    = "domain-c9"                               # vcf-m02-cl01
DS_MOREF    = "datastore-15"                            # vSAN datastore
PG_MOREF    = "dvportgroup-21"                          # vcf-m02-cl01-vds01-pg-mgmt VLAN 114
VNA_NODE_IP = "192.168.114.106"


def main():
    dry = "--dry-run" in sys.argv
    nsx = lab.Nsx()

    vna_path = (
        f"/infra/sites/default/enforcement-points/default"
        f"/virtual-network-appliance-clusters/{lab.VNA_CLUSTER_ID}"
    )

    # ── 1. VNA cluster ────────────────────────────────────────────────────────
    print(f"\n[1/6] VNA cluster '{lab.VNA_CLUSTER_ID}' (MEDIUM, VPC_SERVICES)...")
    nsx.patch(VNA_BASE_PATH, {
        "resource_type": "VirtualNetworkApplianceCluster",
        "display_name": lab.VNA_CLUSTER_ID,
        "appliance_form_factor": "MEDIUM",
        "appliance_type": "VirtualNetworkAppliance",
        "service_type": "VPC_SERVICES",
    }, dry_run=dry)
    print("  ✓ VNA cluster created")

    # ── 2. VNA node ───────────────────────────────────────────────────────────
    print(f"\n[2/6] VNA node vcf-m02-vna01 ({VNA_NODE_IP})...")
    nsx.put(VNA_NODE_PATH, {
        "resource_type": "VirtualNetworkAppliance",
        "id": "vcf-m02-vna01",
        "display_name": "vcf-m02-vna01",
        "hostname": "vcf-m02-vna01.rtolab.local",
        "vm_deployment_config": {
            "compute_manager_id": CM_ID,
            "cluster_or_resource_pool_id": CL_MOREF,
            "datastore_id": DS_MOREF,
            "reservation_info": {
                "memory_reservation": {"reservation_percentage": 100},
                "cpu_reservation": {"reservation_in_shares": "HIGH_PRIORITY"},
            },
        },
        "management_interface": {
            "network_id": PG_MOREF,
            "ip_assignment_specs": [{
                "ip_assignment_type": "StaticIpv4",
                "management_port_subnets": [{"ip_addresses": [VNA_NODE_IP], "prefix_length": 24}],
                "default_gateway": ["192.168.114.254"],
            }],
        },
    }, dry_run=dry)
    print("  ✓ VNA node submitted")

    # ── 3. Wait for VNA cluster to have members (node ready) ──────────────────
    if dry:
        print("\n[3/6] [DryRun] 跳過等候")
    else:
        print("\n[3/6] 等候 VNA cluster.members 非空（node 就緒，最多 30 分鐘）...")
        deadline = time.time() + 30 * 60
        while time.time() < deadline:
            time.sleep(30)
            ts = time.strftime("%H:%M:%S")
            try:
                cl = nsx.get(VNA_BASE_PATH)
                members = cl.get("members", [])
                print(f"  [{ts}] members={len(members)}")
                if members:
                    print(f"  ✓ VNA node ready: {members[0].get('appliance_path','?')}")
                    break
            except Exception as e:
                print(f"  [{ts}] err: {e}")
        else:
            print("  ⚠ 30 分鐘仍無 member — 繼續（profile 等下再確認）")

    # ── 4. Update VPC profile with service_gateway + SNAT ─────────────────────
    print(f"\n[4/6] Update VPC profile '{lab.VPC_PROFILE_ID}' → service_gateway + SNAT...")
    nsx.patch(
        f"/policy/api/v1/orgs/default/projects/{lab.PROJECT_ID}/vpc-connectivity-profiles/{lab.VPC_PROFILE_ID}",
        {
            "resource_type": "VpcConnectivityProfile",
            "display_name": lab.VPC_PROFILE_ID,
            "transit_gateway_path": f"/orgs/default/projects/{lab.PROJECT_ID}/transit-gateways/default",
            "external_ip_blocks": [f"/infra/ip-blocks/{lab.EXT_IPBLOCK_ID}"],
            "private_tgw_ip_blocks": [f"/infra/ip-blocks/{lab.PRIV_TGW_ID}"],
            "service_gateway": {
                "enable": True,
                "edge_cluster_paths": [vna_path],
                "nat_config": {
                    "enable_default_snat": True,
                    "auto_snat_ip_block": f"/infra/ip-blocks/{lab.EXT_IPBLOCK_ID}",
                },
            },
        },
        dry_run=dry,
    )
    print("  ✓ VPC profile: service_gateway + SNAT 已設")

    # ── 5. DistributedVlanConnection ──────────────────────────────────────────
    print(f"\n[5/6] DistributedVlanConnection '{lab.DVC_ID}' (VLAN 114)...")
    nsx.put(
        f"/policy/api/v1/infra/distributed-vlan-connections/{lab.DVC_ID}",
        {
            "resource_type": "DistributedVlanConnection",
            "display_name": lab.DVC_ID,
            "vlan_id": 114,
            "gateway_addresses": ["192.168.114.254/24"],
            "associated_ip_block_paths": [f"/infra/ip-blocks/{lab.EXT_IPBLOCK_ID}"],
        },
        dry_run=dry,
    )
    print("  ✓ DVC created")

    # ── 6. TransitGatewayAttachment ───────────────────────────────────────────
    print(f"\n[6/6] TransitGatewayAttachment '{lab.TGW_ATTACH_ID}'...")
    nsx.put(
        f"/policy/api/v1/orgs/default/projects/{lab.PROJECT_ID}/transit-gateways/default/attachments/{lab.TGW_ATTACH_ID}",
        {
            "resource_type": "TransitGatewayAttachment",
            "display_name": lab.TGW_ATTACH_ID,
            "connection_path": f"/infra/distributed-vlan-connections/{lab.DVC_ID}",
        },
        dry_run=dry,
    )
    print("  ✓ TGW attachment created")

    print(f"""
=== Step1b (VNA + DVC + TGW) 完成 ===
  VNA cluster : {vna_path}
  DVC         : /infra/distributed-vlan-connections/{lab.DVC_ID}
  TGW attach  : /orgs/default/projects/{lab.PROJECT_ID}/transit-gateways/default/attachments/{lab.TGW_ATTACH_ID}

下一步：
  python step2_enable_supervisor.py   （等 vCenter wcp 認得 profile 相容後再跑，約 2-5 分鐘）
""")


if __name__ == "__main__":
    main()
