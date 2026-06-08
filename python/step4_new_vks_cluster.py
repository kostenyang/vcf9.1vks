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
    import yaml  # pip install pyyaml
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
        yaml.safe_dump(CLUSTER_MANIFEST, f, sort_keys=False)
        path = f.name
    print(f"kubectl apply -f {path}")
    subprocess.run(["kubectl", "apply", "-f", path], check=True)
    print("\n=== 等候 / 檢查 ===")
    subprocess.run(["kubectl", "get", "cluster", lab.VKS_CLUSTER, "-n", lab.NS_NAME], check=False)
    print("\n取 kubeconfig（CP Ready 後）：")
    print(f"  kubectl-vsphere login --server={lab.SUP_API_VIP} -u {lab.VCUSER} "
          f"--tanzu-kubernetes-cluster-name={lab.VKS_CLUSTER} "
          f"--tanzu-kubernetes-cluster-namespace={lab.NS_NAME} --insecure-skip-tls-verify")


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
