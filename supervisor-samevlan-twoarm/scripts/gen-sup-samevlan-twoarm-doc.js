const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, ImageRun, PageBreak, BorderStyle
} = require('docx');

const SHOTS = 'E:\\9.1\\doc-shots\\vks-3arm';
const OUT   = 'E:\\9.1\\VCF911-Supervisor-SameVLAN-TwoArm.docx';

const C = { blue: '1F4E79', gray: '595959', red: 'C00000', green: '2E7D32', amber: 'B77E00' };
const W_UI = 600;

const H1 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_1, spacing: { before: 340, after: 160 } });
const H2 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_2, spacing: { before: 260, after: 120 } });
const H3 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 100 } });
const P = (t, o = {}) => new Paragraph({
  children: [new TextRun({ text: t, size: o.size || 21, bold: o.bold, color: o.color, italics: o.italics })],
  spacing: { after: o.after != null ? o.after : 110 }, alignment: o.align });
const CODE = t => new Paragraph({
  children: t.split('\n').map((ln, i) => new TextRun({ text: ln, font: 'Consolas', size: 16, break: i ? 1 : 0 })),
  shading: { type: ShadingType.CLEAR, fill: 'F4F4F4' },
  spacing: { before: 70, after: 70 }, indent: { left: 220 } });
const BULLET = t => new Paragraph({
  children: [new TextRun({ text: t, size: 21 })], bullet: { level: 0 }, spacing: { after: 70 } });
const NOTE = (t, fill, color) => new Paragraph({
  children: [new TextRun({ text: t, size: 20, color: color || C.gray })],
  shading: { type: ShadingType.CLEAR, fill: fill || 'FFF6E5' },
  spacing: { before: 90, after: 90 }, indent: { left: 120, right: 120 },
  border: { left: { style: BorderStyle.SINGLE, size: 18, color: color || C.amber } } });
const PB = () => new Paragraph({ children: [new PageBreak()] });

const TOTAL = 9000;
function table(headers, rows, pct) {
  const widths = pct.map(p => Math.round(TOTAL * p / 100));
  const hdr = new TableRow({ tableHeader: true, children: headers.map((h, i) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA },
    shading: { type: ShadingType.CLEAR, fill: C.blue },
    children: [new Paragraph({ children: [new TextRun({ text: h, bold: true, color: 'FFFFFF', size: 19 })] })] })) });
  const body = rows.map((r, ri) => new TableRow({ children: r.map((c, i) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA },
    shading: ri % 2 ? { type: ShadingType.CLEAR, fill: 'F7F9FC' } : undefined,
    children: [new Paragraph({ children: [new TextRun({ text: String(c), size: 18 })] })] })) }));
  return new Table({ rows: [hdr].concat(body), columnWidths: widths, width: { size: TOTAL, type: WidthType.DXA } });
}
function pngSize(p) { const b = fs.readFileSync(p); return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }; }
let figNo = 0;
function fig(dir, file, caption, maxW) {
  const p = path.join(dir, file);
  const out = []; figNo++;
  if (fs.existsSync(p)) {
    const { w, h } = pngSize(p); const cw = maxW || W_UI; const ch = Math.round(cw * h / w);
    out.push(new Paragraph({ children: [new ImageRun({ type: 'png', data: fs.readFileSync(p), transformation: { width: cw, height: ch } })],
      alignment: AlignmentType.CENTER, spacing: { before: 140, after: 40 } }));
  } else {
    out.push(new Paragraph({ children: [new TextRun({ text: '[ 缺圖:' + file + ' ]', italics: true, color: C.red, size: 18 })], alignment: AlignmentType.CENTER }));
  }
  out.push(new Paragraph({ children: [new TextRun({ text: '圖 ' + figNo + '\u3000' + caption, size: 18, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 180 } }));
  return out;
}
const F = (f, c, w) => fig(SHOTS, f, c, w);
const clean = t => t.replace(/\r/g, '')
  .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, '')
  .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
  .trim();
const cli = f => { const p = path.join(SHOTS, 'cli', f); return fs.existsSync(p) ? clean(fs.readFileSync(p, 'utf8')) : '[缺:' + f + ']'; };

const doc = new Document({
  styles: { default: {
    heading1: { run: { size: 30, bold: true, color: C.blue }, paragraph: { spacing: { before: 340, after: 160 } } },
    heading2: { run: { size: 25, bold: true, color: C.blue }, paragraph: { spacing: { before: 260, after: 120 } } },
    heading3: { run: { size: 22, bold: true, color: '2E5F8A' }, paragraph: { spacing: { before: 200, after: 100 } } },
    document: { run: { font: 'Microsoft JhengHei', size: 21 } } } },
  sections: [{ properties: { page: { margin: { top: 900, bottom: 900, left: 1000, right: 1000 } } }, children: [

    // ── 封面 ──
    new Paragraph({ children: [new TextRun({ text: '', size: 24 })], spacing: { after: 1800 } }),
    new Paragraph({ children: [new TextRun({ text: 'vSphere Supervisor 網路設計實測', size: 44, bold: true, color: C.blue })], alignment: AlignmentType.CENTER }),
    new Paragraph({ children: [new TextRun({ text: '管理網與工作負載網同 VLAN + 三隻腳負載平衡器', size: 32, bold: true, color: C.blue })], alignment: AlignmentType.CENTER, spacing: { after: 300 } }),
    new Paragraph({ children: [new TextRun({ text: 'VCF 9.1.1｜VDS + Foundation Load Balancer（Two Arm）', size: 24, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 160 } }),
    new Paragraph({ children: [new TextRun({ text: '安裝步驟、驗證方法與兩條網路硬性限制', size: 22, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 900 } }),
    new Paragraph({ children: [new TextRun({ text: '實作日期:2026-09-29', size: 21 })], alignment: AlignmentType.CENTER }),
    new Paragraph({ children: [new TextRun({ text: '環境:vcf-m02-vc01.home.lab / cluster m01-cl01 / Supervisor vcf-m02-sup01', size: 19, color: C.gray })], alignment: AlignmentType.CENTER }),
    PB(),

    // ── 目錄 ──
    H1('目錄'),
    P('一、摘要與結論'),
    P('二、測試目的與環境'),
    P('三、兩條網路硬性限制（本文重點）'),
    P('四、網路規劃與前置設定'),
    P('五、逐步安裝（Activate a Supervisor 精靈）'),
    P('六、部署過程與暫時性訊息'),
    P('七、結果驗證'),
    P('八、客戶場景建議'),
    P('附錄 A:指令彙整'),
    P('附錄 B:CLI 輸出'),
    PB(),

    // ── 一 ──
    H1('一、摘要與結論'),
    P('本文回答兩個設計問題:Supervisor 的管理網路（Management Network）與工作負載網路（Workload Network）可不可以放在同一個 VLAN?以及 Foundation Load Balancer 能不能跑「三隻腳」（Two Arm）架構?'),
    P('結論:', { bold: true }),
    table(['問題', '答案', '依據'],
      [['mgmt 與 workload 同一個 VLAN', '✅ 可以', '本文實測部署成功;Supervisor CP VM 兩張網卡都落在 VLAN 0'],
       ['mgmt 與 workload 同一個網段（subnet）', '❌ 不行', 'wcpsvc 在 FINISH 階段擋下,兩條規則互鎖（見第三章）'],
       ['三隻腳（Two Arm）Foundation Load Balancer', '✅ 可以', 'FLB VM 實際配置 3 張網卡,分屬三個 port group'],
       ['Transit Network 可以和 mgmt 同 VLAN', '✅ 可以', 'Transit = Step 5 的 workload network,本文即放在 VLAN 0']],
      [32, 14, 54]),
    NOTE('一句話:同 VLAN 可以,同 subnet 不行。三隻腳需要三個不同的 port group 與三個互不重疊的網段。', 'E8F5E9', C.green),
    P(''),
    BULLET('部署耗時:20:49 送出 → 21:35 RUNNING,約 46 分鐘(3 台主機、CP HA 關閉)。'),
    BULLET('Supervisor API Endpoint = 192.168.15.64(FLB 的 Virtual IP）。'),
    BULLET('Kubernetes 版本 v1.34.9+vmware.1-vsc9.1.1.0-25712839。'),
    PB(),

    // ── 二 ──
    H1('二、測試目的與環境'),
    H2('2.1 為什麼要測這個'),
    P('客戶端常見兩種限制:一是實體網路只給得出一個 VLAN(或不願為 K8s 另外開 VLAN、改 trunk);二是想讓負載平衡器的前端(對外服務)與後端(pod/node)走不同介面,也就是所謂三隻腳架構。這兩件事在 VCF 9.1.1 的 VDS + Foundation Load Balancer 組合下到底行不行,官方文件沒有正面說明,因此實測。'),
    H2('2.2 環境'),
    table(['項目', '值'],
      [['vCenter', 'vcf-m02-vc01.home.lab（9.1.1）'],
       ['Cluster', 'm01-cl01,3 台 ESXi 9.1.1,vSAN'],
       ['VDS', 'm01-cl01-vds01'],
       ['Supervisor', 'vcf-m02-sup01,Control Plane HA = Disabled'],
       ['網路堆疊', 'vSphere Distributed Switch (VDS)（非 NSX VPC）'],
       ['負載平衡器', 'Foundation Load Balancer（不使用 Avi / HAProxy）'],
       ['L3 gateway / NTP', 'RouterOS 10.0.1.254（lab router）'],
       ['DNS', '10.0.0.200（AD），workload 端改指 RouterOS 10.0.1.254']],
      [26, 74]),
    NOTE('Foundation Load Balancer 是 VCF 9.x 內建的輕量負載平衡器,不需要額外授權或另外部署 Avi Controller,適合小型或 PoC 環境。', 'FFF6E5', C.amber),
    PB(),

    // ── 三 ──
    H1('三、兩條網路硬性限制（本文重點）'),
    P('第一次嘗試時,我把 mgmt 與 workload 兩個 port group 都放在 VLAN 0、同一個 10.0.0.0/23 網段,精靈前七步都通過,但按下 FINISH 被擋下:'),
    ...F('19-finish.png', 'FINISH 被 wcpsvc 擋下:vcenter.wcp.network.static.overlapping.modes.error'),
    H2('3.1 規則一:重疊的網路必須「模式一致」（伺服器端）'),
    P('vSphere Client 只顯示 raw message key,沒有翻譯。到 vCenter 把 wcpsvc 的字串挖出來,才看得到真正的訊息:'),
    CODE('root@vcf-m02-vc01 [ ~ ]# strings /usr/lib/vmware-wcp/wcpsvc | grep -ao \\\n'
       + '  "Networks %s and %s have overlapping portgroup(s) and/or subnets, but do not have matching modes"\n'
       + 'Networks %s and %s have overlapping portgroup(s) and/or subnets, but do not have matching modes\n\n'
       + 'root@vcf-m02-vc01 [ ~ ]# grep -ao "vcenter.wcp.network[a-z.]*overlapping[a-z.]*" /usr/lib/vmware-wcp/wcpsvc | sort -u\n'
       + 'vcenter.wcp.network.dhcp.overlapping.modes.error\n'
       + 'vcenter.wcp.network.static.overlapping.modes.error'),
    P('也就是說:只要兩個 Supervisor network 的 port group 或網段有重疊,它們的其餘設定必須完全一致,否則拒絕。DHCP 模式有對應的另一個 key。'),
    H2('3.2 規則二:三隻腳不能共用 port group（精靈端）'),
    P('既然「重疊就要一致」,直覺的繞法是讓 FLB Management 與 workload 共用同一個 port group。實際改下去,精靈在 Load Balancer 那一步就直接顯示:'),
    CODE('Management, Virtual Server, and Transit Networks cannot use the same port group.'),
    P('這個字串在 wcpsvc 裡面找不到,是精靈（vSphere Client）端的驗證,所以會即時出現在頁面上而不是按 FINISH 才報。'),
    H2('3.3 兩條規則互鎖'),
    P('Two Arm 的 Transit Network 就是 Step 5 設定的 workload network。規則二要求它與 FLB Management 使用不同 port group;但只要兩者 port group 不同而網段相同,就會觸發規則一。因此:'),
    NOTE('🔴 在 VDS + Foundation Load Balancer（Two Arm）下,workload network 與 FLB management network 不可能共用同一個網段 —— 無論怎麼配,一定會撞到其中一條規則。', 'FDECEA', C.red),
    P('但這兩條規則管的都是「port group」與「網段」,沒有一條管 VLAN。所以只要在同一個 VLAN 上準備兩個 port group、給它們各自的網段,就能通過驗證 —— 這正是本文採用的做法。'),
    PB(),

    // ── 四 ──
    H1('四、網路規劃與前置設定'),
    H2('4.1 四個網路'),
    table(['角色', 'Port Group', 'VLAN', '網段 / 範圍', '閘道'],
      [['Supervisor Management', 'SDDC-DPortGroup-VM-Mgmt', '0', '10.0.0.182 - 10.0.0.186 /23', '10.0.0.1'],
       ['FLB Management', 'SDDC-DPortGroup-VM-Mgmt', '0', '10.0.0.187 - 10.0.0.188 /23', '10.0.0.1'],
       ['FLB Virtual Server', 'SDDC-Frontend-VM', '5', '192.168.15.10 - 192.168.15.20 /24；VIP .64 - .95', '192.168.15.254'],
       ['Workload / Transit', 'SDDC-Workload-VM', '0', '172.16.10.10 - 172.16.10.60 /24', '172.16.10.254']],
      [22, 26, 7, 30, 15]),
    NOTE('關鍵點:Supervisor Management 與 Workload 同在 VLAN 0,但是兩個不同的 port group、兩個不重疊的網段。FLB Management 與 Supervisor Management 共用 port group 與網段是允許的（兩者設定完全一致 → 符合規則一的 matching modes）。', 'E8F5E9', C.green),
    H2('4.2 port group 準備'),
    P('SDDC-Workload-VM 與 SDDC-Frontend-VM 建在同一個 VDS（m01-cl01-vds01）上,workload 那個 port group 設 VLAN 0（與管理網同 VLAN）。nested 環境請把安全性三項（Promiscuous / MAC changes / Forged transmits）開成 Accept。'),
    CODE('# govc\n'
       + "govc dvs.portgroup.add -dvs m01-cl01-vds01 -type earlyBinding -vlan 0 SDDC-Workload-VM\n"
       + "govc dvs.portgroup.add -dvs m01-cl01-vds01 -type earlyBinding -vlan 5 SDDC-Frontend-VM\n\n"
       + '# PowerCLI\n'
       + "New-VDPortgroup -VDSwitch m01-cl01-vds01 -Name SDDC-Workload-VM -VlanId 0\n"
       + "New-VDPortgroup -VDSwitch m01-cl01-vds01 -Name SDDC-Frontend-VM -VlanId 5\n\n"
       + '# UI:Networking → VDS → ACTIONS → Distributed Port Group → New;\n'
       + '#     安全性在 dvPortgroup → Edit → Security(三項 Accept)'),
    H2('4.3 在同一個 VLAN 上多開一個網段'),
    P('workload 要跟 mgmt 同 VLAN 又不能同網段,所以這個 VLAN 上必須有第二個閘道。本 lab 直接在 RouterOS 的 VLAN 0 介面（ether1）加第二個位址,並打開 DNS 轉發,讓 workload 端的 DNS / NTP 都指向 router,就不必到處補靜態路由:'),
    CODE('# RouterOS（API 8728;工具 E:\\9.1\\Invoke-RouterOS.ps1）\n'
       + '/ip/address/add =address=172.16.10.254/24 =interface=ether1 =comment=vks-workload-same-vlan\n'
       + '/ip/dns/set =servers=10.0.0.200 =allow-remote-requests=yes\n\n'
       + '# 管理端要能連到 workload 節點時,再補靜態路由\n'
       + 'route add 172.16.10.0 mask 255.255.255.0 10.0.1.254 -p        # Windows\n'
       + 'ip route add 172.16.10.0/24 via 10.0.1.254                    # vCenter / Linux'),
    NOTE('實體環境若閘道在交換器或防火牆上,就是在同一個 SVI / VLAN interface 上加 secondary IP(例如 Cisco 的 ip address <x> secondary)。概念一樣:一個 VLAN、兩個網段、兩個閘道。', 'FFF6E5', C.amber),
    PB(),

    // ── 五 ──
    H1('五、逐步安裝（Activate a Supervisor 精靈）'),
    P('入口:vSphere Client → Workload Management（Supervisor Management）→ Supervisors → ADD SUPERVISOR。'),
    H2('5.1 Step 1｜vCenter Server and Network'),
    P('網路堆疊選 vSphere Distributed Switch (VDS)。選 VDS 之後,後面第 6 步才會出現 Foundation Load Balancer 選項;若選 VCF Networking with VPC 則走 NSX,不在本文範圍。'),
    ...F('03-step1-vds-flb.png', 'Step 1:網路堆疊選 VDS'),
    H2('5.2 Step 2｜Supervisor location'),
    P('填 Supervisor 名稱、選 cluster。本次 Control plane high-availability 關閉（lab 省資源;正式環境建議開啟）。'),
    ...F('04-step2.png', 'Step 2:Supervisor 名稱與 cluster'),
    H2('5.3 Step 3｜Storage'),
    P('三個儲存原則（Control Plane / Ephemeral Disks / Image Cache）都選 vSAN Default Storage Policy。'),
    ...F('05-step3-storage.png', 'Step 3:儲存原則'),
    H2('5.4 Step 4｜Management Network'),
    P('IP Assignment Mode 選 Static,Port Group 選管理 port group（SDDC-DPortGroup-VM-Mgmt,VLAN 0），起始位址 10.0.0.182、共 5 個。NTP 請填可靠時間源（本 lab 為 10.0.1.254),時間不同步會在憑證階段出問題。'),
    ...F('06-step4-mgmt.png', 'Step 4:Supervisor 管理網路'),
    H2('5.5 Step 5｜Workload Network（本文重點）'),
    P('Port Group 選 SDDC-Workload-VM —— 注意 VLAN ID 欄位顯示「VLAN 存取: 0」,與管理網同一個 VLAN。'),
    ...F('07-step5-workload-vlan0.png', 'Step 5:workload port group 選在 VLAN 0（與管理網同 VLAN）'),
    NOTE('圖中 IP Address Range 還是第一次嘗試的 10.0.0.190 - 10.0.0.220(與管理網同網段)—— 這個組合會在 FINISH 被擋。正式設定請改成本文的 172.16.10.10 - 172.16.10.60 / 255.255.255.0 / gw 172.16.10.254。', 'FDECEA', C.red),
    P('另外兩個欄位:'),
    BULLET('Network Name 必須符合 RFC-1123（全小寫）。切換 port group 時,這個欄位會被自動覆寫成 port group 名稱(常含大寫)，要手動改回小寫。'),
    BULLET('Internal Network for Kubernetes Services 維持預設 10.96.0.0/23 即可,這是叢集內部 ClusterIP 網段,不會出現在實體網路上。'),
    BULLET('DNS / NTP 這裡填 10.0.1.254(RouterOS)，因為 workload 網段的回程路由只有 router 知道。'),
    H2('5.6 Step 6｜Load Balancer（三隻腳）'),
    P('Type 選 Foundation Load Balancer,Networks Topology 選 Two Arm。選 Two Arm 之後,右側拓樸圖會多出 Transit Network 這一層,總共三層:Load Balancer Management Network、Virtual Server Network、Transit Network。'),
    ...F('08-step6-twoarm.png', 'Step 6:Networks Topology 選 Two Arm'),
    P('接著分別設定三個網路:'),
    table(['區塊', '設定'],
      [['Management Network', '按 EDIT;Port Group 選 SDDC-DPortGroup-VM-Mgmt;名稱 flb-mgmt-net;10.0.0.187 - 10.0.0.188 / 255.255.254.0 / gw 10.0.0.1'],
       ['Virtual Server Network', '按 EDIT;Port Group 選 SDDC-Frontend-VM;名稱 flb-frontend-net;192.168.15.10 - 192.168.15.20 / 255.255.255.0 / gw 192.168.15.254'],
       ['Virtual IP Address Range(s)', '192.168.15.64 - 192.168.15.95(對外服務的 VIP 池,含 Supervisor API endpoint)'],
       ['Transit Network', '不需另外設定 —— 自動沿用 Step 5 的 workload network（sddc-workload-vm）']],
      [24, 76]),
    P('Management / Virtual Server 的 port group 選擇對話框中,清單預設每頁 4 筆,管理 port group 常在第 2 頁,記得翻頁:'),
    ...F('23-pg2.png', 'port group 選擇對話框:管理 port group 在第 2 頁'),
    P('三個網路都設定完後,Load Balancer 頁面會列出三隻腳。可以看到 Transit Network 確實是 Step 5 的 workload network:'),
    ...F('18-step.png', 'Step 6 完成:Management / Virtual Server / Transit 三隻腳'),
    H2('5.7 Step 7-8｜Advanced Settings 與 Ready to complete'),
    P('Advanced Settings 維持預設。Ready to complete 檢查摘要無誤後按 FINISH。若前述網段規劃正確,不會再出現 overlapping 錯誤。'),
    PB(),

    // ── 六 ──
    H1('六、部署過程與暫時性訊息'),
    P('整個過程約 46 分鐘。中間會出現兩類訊息,都會自行重試成功,不需要介入:'),
    H2('6.1 Timed out waiting for LB service update'),
    P('大約在 CP VM 起來之後持續 12 分鐘左右,訊息本身就註明會重試:'),
    CODE('config=CONFIGURING k8s=READY  Timed out waiting for LB service update.\n'
       + '                              This operation is part of the cluster enablement and will be retried.'),
    H2('6.2 error installing service（velero / tkg / cci-ns）'),
    P('內建的 Supervisor Services 安裝時會先報錯再轉成 Configuring、最後 Running:'),
    CODE("Service: velero.vsphere.vmware.com. error installing service 'velero.vsphere.vmware.com' version '1.9.0-embedded'\n"
       + "Service: tkg.vsphere.vmware.com.    error installing service 'tkg.vsphere.vmware.com' version '3.7.0-embedded+v1.36'\n"
       + '  ↓ 約 2 分鐘後\n'
       + 'Service: tkg.vsphere.vmware.com. Status: Configuring ;; cci-ns.vmware.com. Status: Running ;; velero. Status: Running'),
    H2('6.3 監看方式'),
    P('用 vSphere Automation API 輪詢 config_status 比盯 UI 可靠（UI 的 Recent Tasks 不會顯示這些子步驟）:'),
    CODE("S=$(curl -sk -X POST -u 'administrator@vsphere.local:<pw>' https://<vc>/api/session | tr -d '\"')\n"
       + 'curl -sk -H "vmware-api-session-id: $S" \\\n'
       + '  https://<vc>/api/vcenter/namespace-management/supervisors/summaries'),
    P('本次使用的輪詢腳本為 E:\\9.1\\tools\\watch-sup.sh,輸出記錄在 E:\\9.1\\vcf521-conv\\sup-3arm.log。'),
    PB(),

    // ── 七 ──
    H1('七、結果驗證'),
    H2('7.1 Supervisor 狀態'),
    ...F('24-supervisor-running.png', 'Supervisor Config Status = Running,Control Plane Node Address = 192.168.15.64（FLB VIP）'),
    CODE(cli('sup-summary.json')),
    P('API endpoint 可連通性測試（401 表示 TLS 與認證層正常,只是沒帶憑證）:'),
    CODE("curl -sk -o /dev/null -w '%{http_code}\\n' https://192.168.15.64/healthz\n401"),
    H2('7.2 三隻腳的實證:FLB VM 有 3 張網卡'),
    P('One Arm 的 FLB VM 只有 2 張網卡（ethernet-0/1）。Two Arm 應該是 3 張:'),
    CODE(cli('flb-nic-pg.txt') + '\n\n' + cli('pg-names.txt')),
    table(['網卡', 'Port Group', 'VLAN', '角色 / IP'],
      [['Network adapter 1', 'SDDC-Frontend-VM', '5', 'Virtual Server（192.168.15.10）'],
       ['Network adapter 2', 'SDDC-DPortGroup-VM-Mgmt', '0', 'FLB Management（10.0.0.187）'],
       ['Network adapter 3', 'SDDC-Workload-VM', '0', 'Transit（172.16.10.x）']],
      [22, 34, 8, 36]),
    H2('7.3 同 VLAN 的實證:CP VM 兩張網卡都在 VLAN 0'),
    CODE(cli('cp-nic-pg.txt')),
    P('dvportgroup-24 = SDDC-DPortGroup-VM-Mgmt（VLAN 0）、dvportgroup-159 = SDDC-Workload-VM（VLAN 0）。Supervisor 控制平面 VM 的管理介面與工作負載介面確實落在同一個 VLAN,只是網段不同。'),
    H2('7.4 UI 上的最終網路設定'),
    ...F('26-sup-network.png', 'Configure → Network:Foundation Load Balancer 健康,Networks Topology = Two Arm'),
    ...F('29-workload-net.png', 'Management Network 明細:SDDC-DPortGroup-VM-Mgmt / 10.0.0.182 / 255.255.254.0'),
    ...F('30-workload-net.png', '三個網路一覽:flb-frontend-net、flb-mgmt-net、sddc-workload-vm（Primary）'),
    P('這張表最能說明整個設計:三個網路、三個 port group、三個網段,而其中兩個 port group（SDDC-DPortGroup-VM-Mgmt 與 SDDC-Workload-VM）掛在同一個 VLAN 0 上。'),
    PB(),

    // ── 八 ──
    H1('八、客戶場景建議'),
    H2('8.1 只有一個 VLAN 可用時'),
    BULLET('可行。在該 VLAN 上建兩個 port group（VLAN ID 相同），分別給 Supervisor Management 與 Workload。'),
    BULLET('必須在該 VLAN 的 L3 介面上加第二個網段（secondary IP / 第二個 SVI address），作為 workload 的閘道。'),
    BULLET('workload 網段要能回到 DNS / NTP:最省事的做法是把 workload 的 DNS、NTP 指到該 VLAN 的路由器本身（本 lab 即 RouterOS 10.0.1.254),避免在每台服務器上補靜態路由。'),
    BULLET('管理端（跳板機、vCenter）若要直連 workload 節點除錯,再各自補一條靜態路由即可。'),
    H2('8.2 選 One Arm 還是 Two Arm'),
    table(['', 'One Arm', 'Two Arm（三隻腳）'],
      [['FLB VM 網卡數', '2（Management + Virtual Server）', '3（Management + Virtual Server + Transit）'],
       ['需要的 port group', '2 個', '3 個（不可共用）'],
       ['需要的網段', '2 個不重疊', '3 個不重疊'],
       ['適用', '網段資源少、架構簡單', '前端與後端流量要分離、或既有網路就是這樣切的']],
      [22, 36, 42]),
    H2('8.3 常見踩點'),
    table(['狀況', '原因 / 處理'],
      [['FINISH 報 vcenter.wcp.network.static.overlapping.modes.error', '兩個網路的網段重疊而其他設定不一致。把 workload 換到獨立網段。'],
       ['Load Balancer 頁面顯示 cannot use the same port group', 'Two Arm 的三隻腳被指到同一個 port group。至少要三個不同 port group。'],
       ['名稱 XXX 必須符合 RFC-1123', '切換 port group 時 Network Name 被自動帶成 port group 名稱(含大寫)。改成全小寫。'],
       ['在指定的範圍內找到保留的 IP 位址', 'IP 範圍內有已被使用的位址。先掃過再填,或把範圍挪到乾淨的區段。'],
       ['Timed out waiting for LB service update', '正常現象,會自動重試,約 10～15 分鐘。'],
       ['error installing service velero / tkg', '正常現象,內建 Supervisor Services 安裝過程,會自行完成。']],
      [42, 58]),
    PB(),

    // ── 附錄 ──
    H1('附錄 A:指令彙整'),
    CODE('### 連線\n'
       + "export GOVC_URL='https://vcf-m02-vc01.home.lab' GOVC_USERNAME='administrator@vsphere.local' \\\n"
       + "       GOVC_PASSWORD='<pw>' GOVC_INSECURE=1\n"
       + 'export MSYS_NO_PATHCONV=1        # Git-Bash 必加,否則 inventory 路徑被轉成 C:\\...\n\n'
       + '### port group\n'
       + 'govc dvs.portgroup.add -dvs m01-cl01-vds01 -type earlyBinding -vlan 0 SDDC-Workload-VM\n'
       + 'govc dvs.portgroup.add -dvs m01-cl01-vds01 -type earlyBinding -vlan 5 SDDC-Frontend-VM\n\n'
       + '### 驗證網卡與 port group\n'
       + "govc device.info -vm '/m01-dc01/vm/Namespaces/vcf-m02-sup01/flb-vcf-m02-sup01 (1)' 'ethernet-*'\n"
       + "govc device.info -json -vm '<vm path>' 'ethernet-*' | \\\n"
       + "  python -c \"import sys,json;d=json.load(sys.stdin);[print(x['deviceInfo']['label'],'->',x['backing']['port']['portgroupKey']) for x in d['devices']]\"\n"
       + 'govc object.collect -s dvportgroup-159 name\n\n'
       + '### Supervisor 狀態\n'
       + "S=$(curl -sk -X POST -u 'administrator@vsphere.local:<pw>' https://<vc>/api/session | tr -d '\"')\n"
       + 'curl -sk -H "vmware-api-session-id: $S" https://<vc>/api/vcenter/namespace-management/supervisors/summaries\n\n'
       + '### 查 wcpsvc 的真實錯誤訊息(vCenter 需先 shell.set --enabled true)\n'
       + "printf 'shell\\n<cmd>\\nexit\\nexit\\n' | plink -ssh -pw '<pw>' root@<vc-ip>\n"
       + 'strings /usr/lib/vmware-wcp/wcpsvc | grep -ao "overlapping[ a-zA-Z_.%]\\{0,120\\}" | sort -u\n\n'
       + '### RouterOS(同 VLAN 加第二網段)\n'
       + '/ip/address/add =address=172.16.10.254/24 =interface=ether1\n'
       + '/ip/dns/set =servers=10.0.0.200 =allow-remote-requests=yes'),
    PB(),
    H1('附錄 B:CLI 輸出'),
    H2('B.1 FLB VM 網卡'),
    CODE(cli('flb-nics.txt')),
    H2('B.2 網卡對應 port group'),
    CODE(cli('flb-nic-pg.txt') + '\n' + cli('cp-nic-pg.txt') + '\n' + cli('pg-names.txt')),
    H2('B.3 wcpsvc 訊息字串'),
    CODE(cli('wcpsvc-strings.txt')),
    H2('B.4 部署時間軸'),
    CODE(cli('timeline.txt')),
  ] }]
});

Packer.toBuffer(doc).then(b => { fs.writeFileSync(OUT, b); console.log('written', OUT, b.length, 'bytes, figures:', figNo); });
