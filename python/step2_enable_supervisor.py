#!/usr/bin/env python3
"""
Step2 — 啟用 Supervisor（VPC mode）。

  POST /api/vcenter/namespace-management/clusters/{cluster_moref}?action=enable

  python step2_enable_supervisor.py [--dry-run]

Body 結構從實機啟用後 GET 對照確認（2026-06-09）：
  - endpoint: /api/vcenter/namespace-management/clusters/domain-c9?action=enable
  - NOT /api/vcenter/namespace-management/supervisors（VCF 9.1 回 404）
  - master_DNS（不是 master_DNS_servers）
  - master_management_network.address_range.address_count = 5（不是 range）
  - vpc_network（不是 nsx_vpc）
"""
import sys
import time
import lab

CLUSTER_MOREF = "domain-c9"   # vcf-m02-cl01（research/05 確認）
STORAGE_POL   = "a9423670-7455-11e8-adc0-fa7ae01bbebc"   # Management Storage Policy - Single Node


def main():
    dry = "--dry-run" in sys.argv
    vc = lab.Vc()

    # 已啟用就跳過
    sums = vc.get("/api/vcenter/namespace-management/supervisors/summaries").get("items", [])
    if any(s.get("info", {}).get("config_status") == "RUNNING" for s in sums):
        print("已有 RUNNING Supervisor，跳過。直接 step3。")
        for s in sums:
            info = s.get("info", {})
            print(f"  {s['supervisor']}  {info.get('config_status')}  {info.get('api_server_cluster_endpoint')}")
        return

    spec = {
        "image_storage": {"storage_policy": STORAGE_POL},
        "ephemeral_storage_policy": STORAGE_POL,
        "master_storage_policy": STORAGE_POL,
        "service_cidr": {"address": lab.SERVICE_CIDR, "prefix": lab.SERVICE_PREFIX},
        "size_hint": "SMALL",
        "master_NTP_servers": lab.NTP_SERVERS,
        "master_DNS": lab.DNS_SERVERS,
        "master_DNS_search_domains": lab.DNS_SEARCH,
        "network_provider": "NSX_VPC",
        "master_management_network": {
            "mode": "STATICRANGE",
            "network_segment": {"networks": ["dvportgroup-21"]},
            "address_range": {
                "subnet_mask": "255.255.255.0",
                "starting_address": lab.CP_START_IP,
                "gateway": lab.CP_GATEWAY,
                "address_count": 5,
            },
            "network": "dvportgroup-21",
        },
        "vpc_network": {
            "nsx_project": f"/orgs/default/projects/{lab.PROJECT_ID}",
            "auto_created": True,
            "default_private_cidrs": [{"address": lab.VPC_PRIVATE_CIDR, "prefix": lab.VPC_PRIVATE_PREFIX}],
            "vpc_connectivity_profile": f"/orgs/default/projects/{lab.PROJECT_ID}/vpc-connectivity-profiles/{lab.VPC_PROFILE_ID}",
        },
    }

    if dry:
        import json
        print(f"\n[DryRun] POST /api/vcenter/namespace-management/clusters/{CLUSTER_MOREF}?action=enable")
        print(json.dumps(spec, indent=2))
        return

    print(f"\n送出 Supervisor 啟用（cluster {CLUSTER_MOREF}）...")
    vc.post(
        f"/api/vcenter/namespace-management/clusters/{CLUSTER_MOREF}?action=enable",
        spec,
    )
    print("✓ 已接受 — 等候 RUNNING（最多 90 分鐘）...")

    deadline = time.time() + 90 * 60
    while time.time() < deadline:
        time.sleep(60)
        items = vc.get("/api/vcenter/namespace-management/supervisors/summaries").get("items", [])
        if not items:
            print(f"  [{time.strftime('%H:%M:%S')}] (no items yet)")
            continue
        st = items[0].get("info", {}).get("config_status", "?")
        print(f"  [{time.strftime('%H:%M:%S')}] {st}")
        if st in ("RUNNING", "ERROR"):
            break
    else:
        print("  ⚠ 90 分鐘仍未 RUNNING — 請手動確認")
        return

    if st == "RUNNING":
        sup_id = items[0]["supervisor"]
        endpoint = items[0].get("info", {}).get("api_server_cluster_endpoint", "?")
        print(f"""
=== Supervisor RUNNING ===
  supervisor id : {sup_id}
  API endpoint  : {endpoint}

下一步：
  python step3_new_namespace.py
""")
    else:
        print("  ✗ Supervisor ERROR — 請在 vCenter UI 查看事件")


if __name__ == "__main__":
    main()
