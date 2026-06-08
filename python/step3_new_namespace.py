#!/usr/bin/env python3
"""
Step3 — 建 VKS namespace（對應 Step3-New-Namespace.ps1）。
建 namespace NS_NAME，設 storage policy + access list。

  python step3_new_namespace.py

注意：GET /supervisors 在 9.1 回 404，要用 /supervisors/summaries
      （items[].supervisor / items[].info.config_status）。
"""
import sys
import time
import lab


def main():
    vc = lab.Vc()

    sums = vc.get("/api/vcenter/namespace-management/supervisors/summaries")["items"]
    running = [s for s in sums if s["info"]["config_status"] == "RUNNING"]
    if not running:
        print("✗ 沒有 RUNNING Supervisor，先跑 step2_enable_supervisor.py")
        sys.exit(1)
    sup = running[0]
    sup_id = sup["supervisor"]
    print(f"Supervisor: {sup_id}  ({sup['info']['name']} @ {sup['info']['APIEndpoint']})")

    # 已存在就跳過
    try:
        ex = vc.get(f"/api/vcenter/namespaces/instances/{lab.NS_NAME}")
        print(f"✓ namespace '{lab.NS_NAME}' 已存在 ({ex['config_status']})，跳過。")
        return
    except Exception:
        pass

    # storage policy（挑 Single Node）
    pols = vc.get("/api/vcenter/storage/policies")
    pol = next((p for p in pols if "Single Node" in p["name"]), pols[0])
    print(f"storage policy: {pol['name']}")

    body = {
        "namespace": lab.NS_NAME,
        "supervisor": sup_id,
        "storage_specs": [{"policy": pol["policy"], "limit": 204800}],
        "access_list": [{
            "subject_name": "administrator", "subject_type": "USER",
            "domain": "vsphere.local", "role": "EDIT",
        }],
    }
    vc.post("/api/vcenter/namespaces/instances", body)
    print(f"✓ namespace '{lab.NS_NAME}' 建立中")

    # 輪詢
    deadline = time.time() + 300
    while time.time() < deadline:
        time.sleep(15)
        ns = vc.get(f"/api/vcenter/namespaces/instances/{lab.NS_NAME}")
        print(f"  {ns['config_status']}")
        if ns["config_status"] == "RUNNING":
            break
    print(f"namespace: {ns['config_status']}  → 下一步 step4_new_vks_cluster.py")


if __name__ == "__main__":
    main()
