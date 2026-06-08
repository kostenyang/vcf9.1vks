# Content Library（Supervisor/VKS image 來源）— Script + UI

Supervisor 啟用需要一個 content library 提供 Supervisor / spherelet image。
來源是官方訂閱 URL：`https://wp-content.vmware.com/supervisor/v1/latest/lib.json`

> 🔑 **關鍵教訓（實測踩到）**：用 **REST API** 建 subscribed library 時，**一定要帶
> `subscription_info.ssl_thumbprint`**。少了它，API 回 `RESOURCE_INACCESSIBLE /
> Connection to VCSP server failed` —— 看起來像「連不到（egress 問題）」，其實是
> **vCenter 無法驗證對方 SSL 憑證**。inner vCenter 對 wp-content.vmware.com 的 egress
> 本身是通的（UI 流程會跳憑證信任視窗，按 Yes 就過）。

實測結果：sync 後 7 個 item（`supervisor-9.0.0` / `9.0.2` OVF + `spherelet-v1.28`～`v1.32`）。

---

## 方法一：Script

```powershell
# subscribed（預設，會自動抓 ssl_thumbprint）
pwsh ./common/Step1b-Create-ContentLibrary.ps1 -Mode Subscribed -Name tkg-content-library

# 離線環境：先建 local，再從有網的機器 import TKR OVA
pwsh ./common/Step1b-Create-ContentLibrary.ps1 -Mode Local -Name tkg-content-library
```

腳本要點（[Step1b-Create-ContentLibrary.ps1](Step1b-Create-ContentLibrary.ps1)）：
- subscribed 模式自動用 TLS 連線抓對方憑證的 SHA-1 thumbprint，塞進 `subscription_info.ssl_thumbprint`。
- `on_demand = true`（when needed）：只抓 manifest，內容用到才下載，省空間。
- 已存在同名 library 就跳過（idempotent）。

---

## 方法二：UI（vCenter New Content Library wizard）

`vCenter → Content Libraries → CREATE`，subscribed 時是 **5 步**：

1. **Name and location** — Name（如 `tkg-content-library`）、vCenter Server。
2. **Configure content library** — 選 **Subscribed content library**；
   Subscription URL 填 `https://wp-content.vmware.com/supervisor/v1/latest/lib.json`；
   Download content 選 **when needed**（on-demand）。
   - 按 NEXT 後跳 **Security Alert**（憑證驗證）：顯示 wp-content.vmware.com 的 DigiCert 憑證
     （Broadcom Inc），確認後按 **YES** 信任。← 這步等同 API 的 ssl_thumbprint。
3. **Apply security policy** — 一般留空（不勾 Apply Security Policy）。
4. **Add storage** — 選 vSAN datastore（`vcf-m02-cl01-ds-vsan01`）。
5. **Ready to complete** — Review → **FINISH**。建完自動 sync。

截圖見 [../screenshots/](../screenshots/)（`10-*`～`15-*`，需從操作端機器複製進 repo）。

---

## 指派給 Supervisor

content library 建好後，Supervisor 啟用 wizard 的 **Advanced Settings** 步驟（或事後
`Supervisor Management → Content Distribution`）指派這個 library；Supervisor 才有 image 可用。
