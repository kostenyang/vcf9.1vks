# Pod 掛 NFS PVC

VKS（或任何 vSphere CSI 當預設 StorageClass 的叢集）上，預設的 PVC 只會開 **vSphere block volume**（RWO），
不會掛 NFS。要用 NFS 必須自己宣告 PV，再用 PVC 綁它。

完整可 apply 的檔案：[`nfs-pv-pvc-pod.yaml`](nfs-pv-pvc-pod.yaml)（PV + PVC + Pod 三合一）。

## 跟預設 PVC 寫法的差別

| 項目 | vSphere CSI（預設） | NFS |
|---|---|---|
| PV | 動態產生，不用寫 | **要自己寫**（`nfs.server` / `nfs.path`） |
| `storageClassName` | 省略或預設 SC | **自訂名字**（例 `nfs-static`），PV 與 PVC 要一致；留空或用預設 SC 會跑去開 vSphere 碟 |
| `accessModes` | `ReadWriteOnce` | `ReadWriteMany` |
| 綁定 | SC 自動配對 | 建議 PVC 加 `volumeName` 直接指定 PV |
| mount 誰做 | CSI node plugin | **kubelet 在節點上 mount**，NFS server 看到的是節點 IP |

## 完整 YAML

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: app-nfs-pv
spec:
  capacity:
    storage: 100Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-static
  mountOptions: [nfsvers=4.1, hard, noresvport]
  nfs:
    server: 192.0.2.10        # 改成你的 NFS server
    path: /export/app         # 改成你的 export 路徑
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-nfs-pvc
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-static
  volumeName: app-nfs-pv
  resources:
    requests:
      storage: 100Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: nfs-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo \"$(date) $(hostname)\" >> /data/visits.log; tail -f /dev/null"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: app-nfs-pvc
```

## 套用與驗證

```bash
kubectl apply -f nfs-pv-pvc-pod.yaml
kubectl get pv app-nfs-pv            # STATUS 要是 Bound
kubectl get pvc app-nfs-pvc          # STATUS 要是 Bound
kubectl get pod nfs-demo -o wide     # Running；-o wide 看它落在哪個節點
kubectl exec nfs-demo -- cat /data/visits.log
```

在 NFS server 上 `ls -l /export/app/visits.log` 應該看得到同一個檔案。

## NFS server 端要先準備好

1. **export 放行所有節點 IP**：pod 會漂移，mount 又是節點做的，所以不能只放一台。
   ```
   /export/app  172.24.14.0/24(rw,sync,no_root_squash,no_subtree_check)
   ```
   `no_root_squash` 不想開的話，容器要用非 root UID 跑，且目錄權限要配合。
2. 防火牆：NFSv4 只要 **2049/tcp**；NFSv3 另加 111/tcp+udp 與 mountd。
3. 節點要有 NFS client：VKS 的 Photon / Ubuntu TKr 映像都內建；自建節點要裝 `nfs-utils` / `nfs-common`。
4. **不要掛到 VSP 管理叢集**（`scmp*`/`vcf-*-vsp*` 那套 K8s 是 fleet 自己用的），workload 放 VKS guest cluster。

## 常見錯誤

| 症狀 | 原因 | 處理 |
|---|---|---|
| PVC 一直 `Pending`，`kubectl describe pvc` 說找不到 PV | `storageClassName` 跟 PV 不一致，或忘了建 PV | 兩邊對齊；加 `volumeName` |
| PVC `Pending` 但 vCenter 裡多了一顆碟 | `storageClassName` 留空 → 跑去預設 vSphere CSI | 明確指定自訂 SC 名字 |
| Pod `ContainerCreating`，事件 `mount failed: wrong fs type, bad option` 或 `No such device` | 節點沒有 NFS client | 節點裝 `nfs-utils`；VKS 換內建映像 |
| 事件 `access denied by server while mounting` | export 沒放行該節點 IP、或路徑打錯 | server 端 `exportfs -v` 看清單；`showmount -e <server>` 從節點測 |
| mount 卡很久後逾時 | 2049 不通 | 從節點 `nc -zv <server> 2049` |
| 寫檔 `Permission denied` | `root_squash` 把 root 壓成 nobody | export 加 `no_root_squash`，或 chown 給容器 UID |

## 要動態配置時

多個 app 各自要一個目錄，不想每次手寫 PV：裝 [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)
建一個 `nfs-csi` StorageClass，之後 PVC 只要 `storageClassName: nfs-csi`。air-gap 環境要先把它的 image 推進 Harbor。

## 替代方案：vSAN File Service

環境有 vSAN File Service 的話，vSphere CSI 本身就能開 RWX 的 file volume——PVC 寫 `accessModes: [ReadWriteMany]`
配上 vSAN 儲存原則即可，不用自己養 NFS server。
