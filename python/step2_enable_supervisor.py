#!/usr/bin/env python3
"""
Step2 — 啟用 Supervisor（VPC mode，對應 Step2-Enable-Supervisor.ps1）。
  POST /api/vcenter/namespace-management/supervisors

  python step2_enable_supervisor.py [--dry-run] [--vpc-profile <id>]

⚠️ 9.1 supervisors API 的 VPC-mode body 官方未完整公開；本 spec 依 lab schema 組出，
   建議先 --dry-run 檢視，或先 UI 啟一次再 GET 對照（method-ui.md 有實機 7 步）。
"""
import sys
import time
import lab


def main():
    dry = "--dry-run" in sys.argv
    vpc_profile = lab.VPC_PROFILE_ID
    if "--vpc-profile" in sys.argv:
        vpc_profile = sys.argv[sys.argv.index("--vpc-profile") + 1]

    vc = lab.Vc()
    nsx = lab.Nsx()

    # 已啟用就跳過（/summaries → items[].info.config_status）
    sums = vc.get("/api/vcenter/namespace-management/supervisors/summaries")["items"]
    if any(s["info"]["config_status"] == "RUNNING" for s in sums):
        print("已有 RUNNING Supervisor，跳過。直接 step3。")
        for s in sums:
            print(f"  {s['supervisor']}  {s['info']['config_status']}  {s['info']['APIEndpoint']}")
        return

    cl = vc.get(f"/api/vcenter/cluster?names={lab.CLUSTER_NAME}")
    cl_id = cl[0]["cluster"]
    pols = vc.get("/api/vcenter/storage/policies")
    pol = next((p for p in pols if "Single Node" in p["name"]), pols[0])
    pol_id = pol["policy"]
    print(f"cluster={cl_id}  storage_policy='{pol['name']}'")

    # content library（TKG）
    lib_id = None
    for l in vc.get("/api/content/library"):
        d = vc.get(f"/api/content/library/{l}")
        if d.get("type") == "SUBSCRIBED" or any(k in d["name"].lower() for k in ("tkg", "tanzu", "vks", "kubernetes")):
            lib_id = l
    if not lib_id:
        print("⚠️ 找不到 TKG content library；先建 subscribed library：")
        print("   https://wp-content.vmware.com/supervisor/v1/latest/lib.json")
        if not dry:
            sys.exit(1)

    prof = nsx.get(f"/policy/api/v1/orgs/default/projects/{lab.PROJECT_ID}/vpc-connectivity-profiles/{vpc_profile}")
    mode = "Centralized (edge)" if prof.get("service_gateway", {}).get("edge_cluster_paths") else "Distributed (VNA/DTGW)"
    print(f"VPC profile: {prof['display_name']}  → 模式：{mode}")

    spec = {
        "name": lab.SUP_NAME,
        "control_plane": {
            "count": 3, "size": "SMALL", "storage_policy": pol_id,
            "network": {
                "ip_management": {
                    "dhcp_enabled": False,
                    "gateway_address": f"{lab.CP_GATEWAY}/{lab.CP_PREFIX}",
                    "ip_assignments": [{"assignee": "NODE",
                                        "ranges": [{"address": lab.CP_START_IP, "count": 5}]}],
                },
                "services": {
                    "dns": {"servers": lab.DNS_SERVERS, "search_domains": lab.DNS_SEARCH},
                    "ntp": {"servers": lab.NTP_SERVERS},
                },
            },
        },
        "workloads": {
            "images": {"kubernetes_content_library": lib_id},
            "edge": {"provider": "NSX_VPC"},
            "network": {
                "network_type": "NSX_VPC",
                "ip_management": {
                    "dhcp_enabled": False,
                    "ip_assignments": [{"assignee": "SERVICE",
                                        "ranges": [{"address": lab.SERVICE_CIDR, "count": 512}]}],
                },
                "nsx_vpc": {
                    "nsx_project": f"/orgs/default/projects/{lab.PROJECT_ID}",
                    "vpc_connectivity_profile": prof["path"],
                    "default_private_cidrs": [{"address": lab.VPC_PRIVATE_CIDR, "prefix": lab.VPC_PRIVATE_PREFIX}],
                },
                "services": {
                    "dns": {"servers": lab.DNS_SERVERS, "search_domains": lab.DNS_SEARCH},
                    "ntp": {"servers": lab.NTP_SERVERS},
                },
            },
            "storage": {"ephemeral_storage_policy": pol_id, "image_storage_policy": pol_id},
        },
    }

    if dry:
        import json
        print("\n[DryRun] POST /api/vcenter/namespace-management/supervisors")
        print(json.dumps(spec, indent=2))
        return

    print("\n送出 Supervisor 啟用...")
    vc.post("/api/vcenter/namespace-management/supervisors", spec)
    print("✓ 已接受")

    deadline = time.time() + 90 * 60
    while time.time() < deadline:
        time.sleep(60)
        m = vc.get("/api/vcenter/namespace-management/supervisors/summaries")["items"][0]
        st = m["info"]["config_status"]
        print(f"  {st}")
        if st in ("RUNNING", "ERROR"):
            break


if __name__ == "__main__":
    main()
