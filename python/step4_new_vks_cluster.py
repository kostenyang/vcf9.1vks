#!/usr/bin/env python3
"""
Step4 — 建 VKS cluster（對應 Step4-New-VksCluster.ps1 + common/vks-cluster.yaml）。

「起 VKS」的核心：把 Cluster CR 套到 Supervisor 的 guest namespace。

前置（一次性）：
  1. Supervisor RUNNING、namespace NS_NAME RUNNING
  2. Supervisor 掛「兩個」content library：Supervisor image + TKG node-image(v2)
     （少了 node-image library → tkr-resolver webhook 退「Could not resolve KR/OSImage」）
  3. 先用 vSphere plugin 登入（產生 kubeconfig context）：
       kubectl-vsphere login --server=192.168.114.132 \
         -u administrator@vsphere.local --insecure-skip-tls-verify
       kubectl config use-context vks-automation

用法：
  python step4_new_vks_cluster.py            # 寫 manifest 並 kubectl apply
  python step4_new_vks_cluster.py --print     # 只印 manifest（不 apply）
  python step4_new_vks_cluster.py --client     # 用 kubernetes python client apply（需 pip install kubernetes）

實測可用組合（2026-06-08）：builtin-generic-v3.6.0 + v1.34.2 + best-effort-small。
踩過的兩個坑（已內建修正）：
  - pod CIDR 不可用預設 192.168.0.0/16（會撞管理網段 192.168.114.0/24）→ 用 100.96.0.0/11
  - nested 太慢，CP 可能 >60min；用 controlPlane.healthCheck 把 MHC nodeStartupTimeout 拉到 4h
"""
import subprocess
import sys
import tempfile

import lab

CLUSTER_MANIFEST = {
    "apiVersion": "cluster.x-k8s.io/v1beta2",
    "kind": "Cluster",
    "metadata": {"name": lab.VKS_CLUSTER, "namespace": lab.NS_NAME},
    "spec": {
        "clusterNetwork": {
            # pod CIDR 避開管理網段 192.168.114.0/24 + VPC 172.28/29/30 + service 10.96/12
            "services": {"cidrBlocks": ["10.96.0.0/12"]},
            "pods": {"cidrBlocks": ["100.96.0.0/11"]},
            "serviceDomain": "cluster.local",
        },
        "topology": {
            "classRef": {"name": "builtin-generic-v3.6.0", "namespace": "vmware-system-vks-public"},
            "version": "v1.34.2",
            "controlPlane": {
                "replicas": 1,
                # MHC 直接 patch 被 VKS RBAC 擋；從 topology 覆寫拉長到 4h（nested 慢）
                "healthCheck": {"checks": {"nodeStartupTimeoutSeconds": 14400}},
            },
            "workers": {
                "machineDeployments": [
                    {"class": "node-pool", "name": "node-pool-1", "replicas": 1}
                ]
            },
            "variables": [
                {"name": "vmClass", "value": "best-effort-small"},
                {"name": "storageClass", "value": "management-storage-policy-single-node"},
            ],
        },
    },
}


def apply_with_kubectl():
    import time
    import yaml  # pip install pyyaml

    # 1. kubectl-vsphere login → 建立 kubeconfig context
    print("=== 登入 Supervisor ===")
    subprocess.run([lab.KUBECTL, "vsphere", "login",
                    f"--server={lab.SUP_API_VIP}",
                    f"--vsphere-username={lab.VCUSER}",
                    f"--vsphere-password={lab.VCPASS}",
                    "--insecure-skip-tls-verify"], check=True)
    subprocess.run([lab.KUBECTL, "config", "use-context", lab.NS_NAME], check=True)

    # 2. Apply Cluster CR（若已存在跳過）
    chk = subprocess.run([lab.KUBECTL, "get", "cluster", lab.VKS_CLUSTER,
                          "-n", lab.NS_NAME, "--ignore-not-found"],
                         capture_output=True, text=True)
    if lab.VKS_CLUSTER in chk.stdout:
        print(f"cluster '{lab.VKS_CLUSTER}' 已存在，跳過建立。")
    else:
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
            yaml.safe_dump(CLUSTER_MANIFEST, f, sort_keys=False)
            path = f.name
        print(f"kubectl apply -f {path}")
        subprocess.run([lab.KUBECTL, "apply", "-f", path], check=True)

    # 3. 輪詢 Provisioned（最多 90 分鐘）
    print("\n=== 等候 cluster Ready（最多 90 分鐘）===")
    deadline = time.time() + 90 * 60
    phase, cp_ready = "", ""
    while time.time() < deadline:
        time.sleep(60)
        r_phase = subprocess.run(
            [lab.KUBECTL, "get", "cluster", lab.VKS_CLUSTER, "-n", lab.NS_NAME,
             "-o", "jsonpath={.status.phase}"],
            capture_output=True, text=True)
        r_cp = subprocess.run(
            [lab.KUBECTL, "get", "cluster", lab.VKS_CLUSTER, "-n", lab.NS_NAME,
             "-o", "jsonpath={.status.controlPlaneReady}"],
            capture_output=True, text=True)
        phase, cp_ready = r_phase.stdout, r_cp.stdout
        ts = time.strftime("%H:%M:%S")
        print(f"  [{ts}] phase={phase} cpReady={cp_ready}")
        if phase == "Provisioned" and cp_ready == "true":
            break
        if phase == "Failed":
            subprocess.run([lab.KUBECTL, "get", "cluster", lab.VKS_CLUSTER,
                            "-n", lab.NS_NAME, "-o", "yaml"])
            break

    # 4. 取 kubeconfig
    if phase == "Provisioned":
        print("\n=== 下載 kubeconfig ===")
        subprocess.run([lab.KUBECTL, "vsphere", "login",
                        f"--server={lab.SUP_API_VIP}",
                        f"--vsphere-username={lab.VCUSER}",
                        f"--vsphere-password={lab.VCPASS}",
                        f"--tanzu-kubernetes-cluster-name={lab.VKS_CLUSTER}",
                        f"--tanzu-kubernetes-cluster-namespace={lab.NS_NAME}",
                        "--insecure-skip-tls-verify"], check=True)
        import os
        kc = os.path.expanduser(f"~\\.kube\\{lab.VKS_CLUSTER}.yaml")
        os.makedirs(os.path.dirname(kc), exist_ok=True)
        flat = subprocess.run([lab.KUBECTL, "config", "view", "--flatten",
                               f"--context={lab.VKS_CLUSTER}"],
                              capture_output=True, text=True)
        with open(kc, "w") as fh:
            fh.write(flat.stdout)
        print(f"✓ kubeconfig: {kc}")
        os.environ["KUBECONFIG"] = kc
        subprocess.run([lab.KUBECTL, "get", "nodes"])
    else:
        print(f"⚠ phase={phase}，未取 kubeconfig。")


def apply_with_client():
    from kubernetes import client, config  # pip install kubernetes
    config.load_kube_config()  # 用 kubectl-vsphere login 後的 context
    api = client.CustomObjectsApi()
    try:
        api.create_namespaced_custom_object(
            group="cluster.x-k8s.io", version="v1beta2",
            namespace=lab.NS_NAME, plural="clusters", body=CLUSTER_MANIFEST)
        print(f"✓ cluster '{lab.VKS_CLUSTER}' created")
    except client.ApiException as e:
        if e.status == 409:
            print(f"cluster '{lab.VKS_CLUSTER}' 已存在，跳過。")
        else:
            raise


def main():
    if "--print" in sys.argv:
        import json
        print(json.dumps(CLUSTER_MANIFEST, indent=2))
        return
    if "--client" in sys.argv:
        apply_with_client()
    else:
        apply_with_kubectl()


if __name__ == "__main__":
    main()
