"""全拆：VKS cluster → namespace → Supervisor → VNA node → VNA cluster → VPC profile → IP blocks

用法：
  python step0_teardown.py           # 實際執行
  python step0_teardown.py --dry-run # 只印操作不執行

⚠️ 拆除順序不可顛倒。"""
import argparse
import subprocess
import sys
import time

# Force UTF-8 output so ✓/⚠ characters print on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from lab import (
    Vc, Nsx,
    SUP_API_VIP, VCUSER, VCPASS,
    NS_NAME, VKS_CLUSTER, SUP_NAME,
    VNA_CLUSTER_ID, DVC_ID, TGW_ATTACH_ID, PROJECT_ID,
    EXT_IPBLOCK_ID, PRIV_TGW_ID, VPC_PROFILE_ID,
    KUBECTL,
)

VNA_BASE  = f"/policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters/{VNA_CLUSTER_ID}"
VNA_NODE  = f"{VNA_BASE}/virtual-network-appliances/vcf-m02-vna01"


def step(n, msg):
    print(f"\n[{n}] {msg}")


def ok(msg):
    print(f"  ✓ {msg}")


def skip(msg):
    print(f"  (skip) {msg}")


def warn(msg):
    print(f"  ⚠ {msg}")


def poll(label, check_fn, interval=30, timeout=900):
    """Poll check_fn() until it returns False (resource gone) or timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(interval)
        exists = check_fn()
        ts = time.strftime("%H:%M:%S")
        print(f"  [{ts}] exists={exists}")
        if not exists:
            return
    warn(f"{label}: still exists after {timeout}s — continuing anyway")


# ─────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    dry = args.dry_run

    vc  = Vc()
    nsx = Nsx()

    # ── 1. 刪 VKS cluster ────────────────────────────────────────────────────
    step("1/9", f"Delete VKS cluster '{VKS_CLUSTER}' in namespace '{NS_NAME}'")
    if dry:
        print(f"  [DryRun] kubectl vsphere login → kubectl delete cluster {VKS_CLUSTER} -n {NS_NAME}")
    else:
        _login_ok = False
        try:
            subprocess.run(
                [KUBECTL, "vsphere", "login",
                 f"--server={SUP_API_VIP}",
                 f"--vsphere-username={VCUSER}",
                 f"--vsphere-password={VCPASS}",
                 "--insecure-skip-tls-verify"],
                check=True, capture_output=True, timeout=30)
            _login_ok = True
        except subprocess.TimeoutExpired:
            warn(f"Supervisor API {SUP_API_VIP}:6443 unreachable (30s timeout), skipping kubectl cluster deletion")
        except subprocess.CalledProcessError as e:
            warn(f"kubectl vsphere login failed ({e.returncode}), skipping cluster deletion")
        except FileNotFoundError:
            warn("kubectl not found, skipping cluster deletion")
        if _login_ok:
            subprocess.run([KUBECTL, "config", "use-context", NS_NAME],
                           check=True, capture_output=True)
            chk = subprocess.run(
                [KUBECTL, "get", "cluster", VKS_CLUSTER, "-n", NS_NAME, "--ignore-not-found"],
                capture_output=True, text=True)
            if VKS_CLUSTER in chk.stdout:
                subprocess.run([KUBECTL, "delete", "cluster", VKS_CLUSTER, "-n", NS_NAME], check=True)
                print("  等候 cluster 刪除（最多 15 分鐘）...")
                def cluster_exists():
                    r = subprocess.run(
                        [KUBECTL, "get", "cluster", VKS_CLUSTER, "-n", NS_NAME, "--ignore-not-found"],
                        capture_output=True, text=True)
                    return VKS_CLUSTER in r.stdout
                poll("VKS cluster", cluster_exists, interval=30, timeout=900)
                ok("cluster gone")
            else:
                skip(f"cluster '{VKS_CLUSTER}' not found")

    # ── 2. 刪 namespace ───────────────────────────────────────────────────────
    step("2/9", f"Delete namespace '{NS_NAME}'")
    if dry:
        print(f"  [DryRun] DELETE /api/vcenter/namespaces/instances/{NS_NAME}")
    else:
        gone = vc.delete(f"/api/vcenter/namespaces/instances/{NS_NAME}")
        if gone:
            print("  等候 namespace 移除...")
            def ns_exists():
                try:
                    vc.get(f"/api/vcenter/namespaces/instances/{NS_NAME}")
                    return True
                except Exception:
                    return False
            poll("namespace", ns_exists, interval=20, timeout=600)
            ok("namespace gone")
        else:
            skip(f"namespace '{NS_NAME}' not found")

    # ── 3. Disable Supervisor ─────────────────────────────────────────────────
    step("3/9", f"Disable Supervisor '{SUP_NAME}'")
    if dry:
        print("  [DryRun] GET summaries → DELETE /api/vcenter/namespace-management/supervisors/{id}")
    else:
        sums = vc.get("/api/vcenter/namespace-management/supervisors/summaries").get("items", [])
        if sums:
            sup_id = sums[0]["supervisor"]
            print(f"  Supervisor id={sup_id}")
            vc.delete(f"/api/vcenter/namespace-management/supervisors/{sup_id}")
            print("  等候 Supervisor disable（最多 60 分鐘）...")
            def sup_exists():
                items = vc.get("/api/vcenter/namespace-management/supervisors/summaries").get("items", [])
                return bool(items)
            poll("Supervisor", sup_exists, interval=60, timeout=3600)
            ok("Supervisor disabled/gone")
        else:
            skip("no Supervisor found")

    # ── 4. 刪 VNA node ────────────────────────────────────────────────────────
    step("4/9", "Delete VNA node 'vcf-m02-vna01'")
    nsx.delete(VNA_NODE, dry_run=dry)
    if not dry:
        print("  等候 VNA node 刪除（最多 10 分鐘）...")
        def vna_node_exists():
            try:
                nsx.get(VNA_NODE)
                return True
            except Exception:
                return False
        poll("VNA node", vna_node_exists, interval=30, timeout=600)
        ok("VNA node gone")

    # ── 5. 刪 VPC Connectivity Profile（必須先於 VNA cluster）──────────────────
    step("5/9", f"Delete VPC Connectivity Profile '{VPC_PROFILE_ID}'")
    nsx.delete(
        f"/policy/api/v1/orgs/default/projects/{PROJECT_ID}/vpc-connectivity-profiles/{VPC_PROFILE_ID}",
        dry_run=dry)
    if not dry:
        ok("VPC profile deleted")

    # ── 6. 刪 VNA cluster（VPC profile 已刪才可刪）───────────────────────────
    step("6/9", f"Delete VNA cluster '{VNA_CLUSTER_ID}'")
    nsx.delete(VNA_BASE, dry_run=dry)
    if not dry:
        time.sleep(10)
        try:
            nsx.get(VNA_BASE)
            warn("VNA cluster 仍存在，可能需要更長時間")
        except Exception:
            ok("VNA cluster gone")

    # ── 7. 刪 TransitGatewayAttachment（必須先於 DVC）────────────────────────
    step("7/9", f"Delete TransitGatewayAttachment '{TGW_ATTACH_ID}'")
    nsx.delete(
        f"/policy/api/v1/orgs/default/projects/{PROJECT_ID}/transit-gateways/default/attachments/{TGW_ATTACH_ID}",
        dry_run=dry)
    if not dry:
        ok("TGW attachment deleted")

    # ── 8. 刪 DistributedVlanConnection（必須先於 IP blocks）─────────────────
    step("8/9", f"Delete DistributedVlanConnection '{DVC_ID}'")
    nsx.delete(f"/policy/api/v1/infra/distributed-vlan-connections/{DVC_ID}", dry_run=dry)
    if not dry:
        ok("DVC deleted")

    # ── 9. 刪 IP blocks ───────────────────────────────────────────────────────
    step("9/9", f"Delete IP blocks ({EXT_IPBLOCK_ID}, {PRIV_TGW_ID})")
    nsx.delete(f"/policy/api/v1/infra/ip-blocks/{EXT_IPBLOCK_ID}", dry_run=dry)
    nsx.delete(f"/policy/api/v1/infra/ip-blocks/{PRIV_TGW_ID}",    dry_run=dry)
    if not dry:
        ok("IP blocks deleted")

    print("""
=== Teardown 完成 ===
  拆除順序：cluster → namespace → Supervisor → VNA node → VPC profile → VNA cluster → DVC → IP blocks
  下一步（重新建立）：
    Python 方式：
      py step1_setup_dtgw.py
      py step2_enable_supervisor.py
      py step3_new_namespace.py
      py step4_new_vks_cluster.py
""")


if __name__ == "__main__":
    main()
