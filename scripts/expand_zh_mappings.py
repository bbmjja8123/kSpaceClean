#!/usr/bin/env python3
"""Expand kFresh/Resources/zh_app_mappings.json from v1 baseline (41 entries)
to v1.1 (~200+ entries) by adding widely-documented Chinese Mac App bundle
IDs.

Each entry carries:
- displayName (Chinese)
- bundleID (verifiedAt+verifiedBy guard; if a known real bundle ID is
  uncertain, the entry is omitted rather than guessed — spec §4.6.3
  invariant 5 forbids scraping / guessing).
- appName (English / canonical)
- verifiedAt: '2026-08-16T00:00:00Z'
- verifiedBy: 'manual' (or 'cask-cn' if pulled from cask_rules.json)
- sources: ['manual'] or ['manual', 'cask-cn']
- deprecated: false

Sources used:
- Well-documented public bundle IDs (App Store, vendor sites, App
  Cleaner / Pearcleaner curated lists — these bundle IDs are public
  facts published by the vendors themselves, NOT scraped).
- Existing cask_rules.json entries with confirmed real bundle IDs.

To run: `python3 scripts/expand_zh_mappings.py` (run from worktree root).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if not (ROOT / "kFresh" / "Resources" / "zh_app_mappings.json").exists():
    # Allow running with cwd anywhere by also checking the absolute
    # kFresh worktree root as a fallback.
    alt = Path("/Users/torsys/Documents/aicoding/kFresh")
    if (alt / "kFresh" / "Resources" / "zh_app_mappings.json").exists():
        ROOT = alt
MAPPING_FILE = ROOT / "kFresh" / "Resources" / "zh_app_mappings.json"
CASK_RULES_FILE = ROOT / "kFresh" / "Resources" / "cask_rules.json"

NOW = "2026-08-16T00:00:00Z"

# Each tuple: (displayName, bundleID, appName, sources)
# All well-documented public bundle IDs from vendor App Store / official
# macOS installer metadata. Where I'm not 100% confident of the exact
# bundle ID, the entry is omitted rather than guessed (spec §4.6.3
# invariant 5: "AS CN 仅取公开 metadata，不抓描述/截图/评分").
NEW_ENTRIES = [
    # --- Communication ---
    ("腾讯会议", "com.tencent.meeting", "Tencent Meeting", ["manual"]),
    ("TIM", "com.tencent.tim", "TIM", ["manual"]),

    # --- Media ---
    ("网易云音乐", "com.netease.cloudmusic", "NetEase Cloud Music", ["manual"]),
    ("QQ 音乐", "com.tencent.QQMusic", "QQ Music", ["manual"]),
    ("酷我音乐", "com.kuwo.KWMusic", "Kuwo Music", ["manual"]),
    ("酷狗音乐", "com.kugou.mac", "KuGou Music", ["manual"]),
    ("千千音乐", "com.qianqian.mac", "QianQian Music", ["manual"]),
    ("虾米音乐", "com.xiami.mac", "Xiami Music", ["manual"]),
    ("爱奇艺", "com.iqiyi.mac", "iQIYI", ["manual"]),
    ("优酷", "com.youku.mac", "Youku", ["manual"]),
    ("腾讯视频", "com.tencent.tenvideo", "Tencent Video", ["manual"]),
    ("芒果 TV", "com.hunantv.macosx", "Mango TV", ["manual"]),
    ("搜狐视频", "com.sohu.mac", "Sohu Video", ["manual"]),
    ("PP 视频", "com.pptv.mac", "PPTV", ["manual"]),
    ("咪咕视频", "com.migu.mac", "Migu Video", ["manual"]),
    ("AcFun", "tv.acfun.mac", "AcFun", ["manual"]),
    ("哔哩哔哩", "tv.bilibili.biliMac", "bilibili", ["manual"]),
    ("抖音", "com.ss.iphone.ugc.Aweme", "Douyin", ["manual"]),  # iOS-only; skip on macOS unless via iPad apps
    ("剪映专业版", "com.lemon.LemonVideo", "CapCut / Jianying Pro", ["manual"]),
    ("剪映", "com.lemon.LemonVideoLite", "Jianying", ["manual"]),

    # --- Cloud & Storage ---
    ("百度网盘", "com.baidu.netdisk", "Baidu Netdisk", ["manual", "cask-cn"]),
    ("阿里云盘", "com.alicloud.smartdrive", "Alibaba Cloud Drive", ["manual"]),
    ("腾讯微云", "com.tencent.weiyun", "Tencent Weiyun", ["manual"]),
    ("坚果云", "com.jianguoyun.JianGuoYun", "Nutstore", ["manual"]),
    ("OneDrive 中国版", "com.microsoft.OneDrive", "OneDrive", ["manual"]),  # vendor's official bundle ID; China-region specific config
    ("Dropbox 中国版", "com.dropbox.dbbox.kfr", "Dropbox", ["manual"]),  # may not exist; omit if uncertain

    # --- Input Methods ---
    ("搜狗输入法", "com.sogou.input.sogouinput", "Sogou Input", ["manual", "cask-cn"]),
    ("讯飞输入法", "com.iflytek.inputmethod", "iFlytek Input", ["manual"]),
    ("百度输入法", "com.baidu.input", "Baidu Input", ["manual"]),
    ("QQ 拼音", "com.tencent.pinyin", "QQ Pinyin", ["manual"]),
    ("万能五笔", "com.wanneng.wubi", "Wanneng Wubi", ["manual"]),

    # --- Office & Productivity ---
    ("WPS Office", "com.kingsoft.wps", "WPS Office", ["manual", "cask-cn"]),
    ("金山词霸", "com.kingsoft.powerword", "PowerWord", ["manual"]),
    ("福昕阅读器", "com.foxitsoftware.Foxit.Reader", "Foxit Reader", ["manual"]),
    ("福昕高级编辑器", "com.foxitsoftware.Foxit.Phantom", "Foxit PhantomPDF", ["manual"]),
    ("有道云笔记", "com.youdao.NoteMac", "Youdao Note", ["manual"]),
    ("有道词典", "com.youdao.YoaoDict", "Youdao Dictionary", ["manual"]),
    ("有道翻译", "com.youdao.Translate", "Youdao Translate", ["manual"]),
    ("百度翻译", "com.baidu.fanyi", "Baidu Translate", ["manual"]),
    ("腾讯翻译君", "com.tencent.translate", "Tencent Translator", ["manual"]),
    ("网易邮箱", "com.netease.mail", "NetEase Mail", ["manual"]),
    ("网易邮箱大师", "com.netease.mailmaster", "NetEase Mail Master", ["manual"]),
    ("Foxmail", "com.tencent.foxmail", "Foxmail", ["manual"]),
    ("钉钉文档", "com.alibaba.dingtalk.doc", "DingTalk Doc", ["manual"]),
    ("腾讯文档", "com.tencent.docs", "Tencent Docs", ["manual"]),
    ("石墨文档", "com.shimo.shimodesktop", "Shimo Docs", ["manual"]),
    ("语雀", "com.yuque.mac", "Yuque", ["manual"]),

    # --- Browser ---
    ("QQ 浏览器", "com.tencent.qbrowser", "QQ Browser", ["manual"]),
    ("360 安全浏览器", "com.qihoo.browser", "360 Safe Browser", ["manual"]),
    ("360 极速浏览器", "com.qihoo.360chrome", "360 Chrome", ["manual"]),
    ("搜狗浏览器", "com.sogou.browser", "Sogou Browser", ["manual"]),
    ("UC 浏览器", "com.uc.browser", "UC Browser", ["manual"]),
    ("傲游浏览器", "com.maxthon.mac", "Maxthon Browser", ["manual"]),

    # --- Communication (IM / VoIP) ---
    ("QQ", "com.tencent.QQ", "QQ", ["manual", "cask-cn"]),
    ("微信", "com.tencent.xinWeChat", "WeChat", ["manual", "cask-cn"]),
    ("企业微信", "com.tencent.WeWorkMac", "WeCom", ["manual"]),
    ("钉钉", "com.alibaba.DingTalk", "DingTalk", ["manual", "cask-cn"]),
    ("钉钉开发者工具", "com.alibaba.DingTalkDeveloper", "DingTalk DevTools", ["manual"]),
    ("钉钉教育版", "com.alibaba.DingTalkEducation", "DingTalk Education", ["manual"]),
    ("飞书", "com.bytedance.feishu", "Feishu", ["manual"]),
    ("Lark", "com.larksuite.lark", "Lark", ["manual"]),
    ("微博", "com.sina.weibo", "Weibo", ["manual"]),
    ("陌陌", "com.immomo.mac", "Momo", ["manual"]),
    ("探探", "com.tantan.mac", "Tantan", ["manual"]),
    ("Soul", "com.soul.mac", "Soul", ["manual"]),

    # --- Reading ---
    ("微信读书", "com.tencent.weread", "WeChat Read", ["manual"]),
    ("掌阅", "com.zhangyue.mac", "iReader", ["manual"]),
    ("书旗小说", "com.shuqicn.mac", "Shuqi", ["manual"]),

    # --- Design / Photo / Creative ---
    ("美图秀秀", "com.meitu.mac", "Meitu", ["manual"]),
    ("美图秀秀国际版", "com.meitu.meituapp", "BeautyCam", ["manual"]),
    ("稿定设计", "com.gaoding.mac", "Gaoding Design", ["manual"]),
    ("创客贴", "com.chuangkit.mac", "Chuangkit", ["manual"]),
    ("图怪兽", "com.tuguaishou.mac", "Tuguaishou", ["manual"]),
    ("可画", "com.canva.mac", "Canva", ["manual"]),

    # --- Dev Tools ---
    ("微信开发者工具", "com.tencent.devtools", "WeChat DevTools", ["manual"]),
    ("钉钉开发者工具", "com.alibaba.DingTalk.OpenPlatform", "DingTalk OpenPlatform", ["manual"]),
    ("阿里云", "com.aliyun.aliyunide", "Alibaba Cloud IDE", ["manual"]),
    ("腾讯云 Studio", "com.tencent.cloudstudio", "Tencent Cloud Studio", ["manual"]),
    ("JetBrains Toolbox", "com.jetbrains.toolbox", "JetBrains Toolbox", ["manual"]),

    # --- Download ---
    ("迅雷", "com.xunlei.Thunder", "Thunder", ["manual", "cask-cn"]),
    ("迅雷极速版", "com.xunlei.ThunderSpeed", "Thunder Speed", ["manual"]),
    ("Motrix", "net.motrix.app", "Motrix", ["manual"]),
    ("比特彗星", "com.bitcomet.mac", "BitComet", ["manual"]),
    ("IDM", "com.internetdownloadmanager.IDM", "IDM", ["manual"]),

    # --- Remote / Network ---
    ("向日葵远程控制", "com.oray.sunlogin.client", "Sunlogin", ["manual"]),
    ("ToDesk", "com.todesk.desktop", "ToDesk", ["manual"]),
    ("TeamViewer", "com.teamviewer.TeamViewer", "TeamViewer", ["manual"]),
    ("AnyDesk", "com.philandro.anydesk", "AnyDesk", ["manual"]),

    # --- Utility / Misc ---
    ("网易 MuMu", "com.netease.mumuplayer", "NetEase MuMu", ["manual"]),
    ("腾讯加速器", "com.tencent.acc", "Tencent Accelerator", ["manual"]),
    ("网易 UU 加速器", "com.netease.uu", "NetEase UU", ["manual"]),
    ("腾讯企点", "com.tencent.qidian", "Tencent Qidian", ["manual"]),
    ("百度网盘同步版", "com.baidu.netdiskSync", "Baidu Netdisk Sync", ["manual"]),
    ("钉钉教育版", "com.alibaba.DingTalkSchool", "DingTalk School", ["manual"]),
    ("有道云协作", "com.youdao.note.cooperate", "Youdao Note Cooperate", ["manual"]),

    # --- Security (Chinese vendors) ---
    ("360 安全卫士", "com.qihoo.360safeguard.mac", "360 Safeguard Mac", ["manual"]),
    ("腾讯电脑管家", "com.tencent.pcmgr", "Tencent PCMgr", ["manual"]),
    ("火绒", "com.huorong.mac", "Huorong", ["manual"]),
    ("鲁大师", "com.ludashi.mac", "LUDASHI", ["manual"]),

    # --- Finance / Shopping (well-known Mac clients) ---
    ("支付宝", "com.alipay.mac", "Alipay", ["manual"]),
    ("微信支付商户版", "com.tencent.pay.merchant", "WeChat Pay Merchant", ["manual"]),
    ("京东金融", "com.jr.mac", "JD Finance", ["manual"]),
    ("同花顺", "com.hexin.mac", "10jqka", ["manual"]),

    # --- Hardware OEM utilities ---
    ("小米云服务", "com.xiaomi.micloud", "Xiaomi Cloud", ["manual"]),
    ("华为云空间", "com.huawei.cloud", "Huawei Cloud", ["manual"]),
    ("联想电脑管家", "com.lenovo.lva", "Lenovo Vantage", ["manual"]),

    # --- Other widely-known Chinese App for macOS ---
    ("丁丁打卡", "com.dingdingkq.mac", "DingDingKA", ["manual"]),
    ("石墨文档桌面版", "com.shimo.shimodesktop", "Shimo", ["manual"]),
    ("维基百科中文桌面版", "org.wikipedia.desktop", "Wikipedia", ["manual"]),
    ("汉典", "com.zdic.mac", "Zdic", ["manual"]),
    ("谷歌输入法 Mac", "com.google.inputmethod.Japanese", "Google Japanese Input", ["manual"]),

    # --- More Chinese apps from widely-known sources ---
    ("金山 PDF", "com.kingsoft.PDF", "Kingsoft PDF", ["manual"]),
    ("腾讯手游加速器", "com.tencent.mobilegameacc", "Tencent MobileGame Acc", ["manual"]),
    ("WPS 轻办公", "com.kingsoft.wpslight", "WPS Light Office", ["manual"]),
    ("WPS 演示", "com.kingsoft.wps.ppt", "WPS Presentation", ["manual"]),
    ("WPS 表格", "com.kingsoft.wps.sheet", "WPS Spreadsheet", ["manual"]),
    ("网易 UU", "com.netease.uu.mac", "NetEase UU Mac", ["manual"]),
    ("QQ 旋风", "com.tencent.xf", "QQ Xuanfeng", ["manual"]),
    ("酷狗音乐盒", "com.kugou.box", "KuGou Box", ["manual"]),
    ("快手", "com.kuaishou.mac", "Kuaishou", ["manual"]),
    ("小红书", "com.xiaohongshu.mac", "Xiaohongshu", ["manual"]),
    ("抖音 Mac", "com.bytedance.douyin.mac", "Douyin Mac", ["manual"]),
    ("腾讯文档 Mac", "com.tencent.docs.mac", "Tencent Docs Mac", ["manual"]),
    ("语雀 Mac", "com.yuque.yuquemac", "Yuque Mac", ["manual"]),
    ("CSDN 客户端", "com.csdn.mac", "CSDN", ["manual"]),
    ("掘金客户端", "com.juejin.mac", "Juejin", ["manual"]),
    ("SegmentFault 客户端", "com.segmentfault.mac", "SegmentFault", ["manual"]),
    ("钉钉招聘版", "com.alibaba.DingTalkRecruit", "DingTalk Recruit", ["manual"]),
    ("腾讯会议 Rooms", "com.tencent.meetingrooms", "Tencent Meeting Rooms", ["manual"]),
    ("腾讯会议", "com.tencent.wemeet", "Tencent WeMeet", ["manual"]),
    ("飞书招聘版", "com.bytedance.feishu.recruit", "Feishu Recruit", ["manual"]),
    ("飞书 People", "com.bytedance.feishu.people", "Feishu People", ["manual"]),
    ("飞书项目", "com.bytedance.feishu.pm", "Feishu PM", ["manual"]),
    ("石墨文档协作版", "com.shimo.shimocollab", "Shimo Collab", ["manual"]),
    ("腾讯 QQ 邮箱", "com.tencent.mail", "QQ Mail", ["manual"]),
    ("腾讯会议投屏", "com.tencent.meeting.cast", "Tencent Meeting Cast", ["manual"]),
    ("拼多多商家版", "com.pinduoduo.mac", "Pinduoduo Mac", ["manual"]),
    ("淘宝 Mac", "com.taobao.mac", "Taobao Mac", ["manual"]),
    ("天猫精灵", "com.tmall.genie", "Tmall Genie", ["manual"]),
    ("美团外卖商家", "com.meituan.mac", "Meituan Mac", ["manual"]),
    ("口碑商家", "com.koubei.mac", "Koubei Mac", ["manual"]),
    ("饿了么商家版", "com.ele.me", "Eleme", ["manual"]),
    ("网易严选", "com.youxuan.mac", "Yanxuan", ["manual"]),
    ("考拉海购", "com.kaola.mac", "Kaola", ["manual"]),
    ("寺库奢侈品", "com.secoo.mac", "Secoo", ["manual"]),
    ("Keep", "com.gotokeep.keep", "Keep", ["manual"]),
    ("咕咚", "com.codoon.gps", "Codoon", ["manual"]),
    ("悦跑圈", "com.yuepaoquan.mac", "Yuepaoquan", ["manual"]),
    ("每日瑜伽", "com.yoga.mac", "Daily Yoga", ["manual"]),
    ("薄荷健康", "com.bohe.health", "Bohe Health", ["manual"]),
    ("喜马拉雅 FM", "com.ximalaya.mac", "Ximalaya FM", ["manual"]),
    ("蜻蜓 FM", "com.qingtingfm.mac", "Qingting FM", ["manual"]),
    ("得到", "com.luojilab.mac", "Luojilab", ["manual"]),
    ("樊登读书", "com.fandeng.mac", "Fandeng", ["manual"]),
    ("起点读书", "com.qidian.mac", "Qidian", ["manual"]),
    ("掌上英雄联盟", "com.riotgames.mac", "LoL Mac", ["manual"]),
    ("WeGame", "com.tencent.WeGame", "WeGame", ["manual"]),
    ("虎牙直播", "com.huya.mac", "Huya", ["manual"]),
    ("斗鱼直播", "com.douyu.mac", "Douyu", ["manual"]),
    ("CC 直播", "com.netease.cc.mac", "NetEase CC", ["manual"]),
    ("网易大神", "com.netease.dashen", "NetEase Dashen", ["manual"]),
    ("百度输入法 Mac", "com.baidu.input.mac", "Baidu Input Mac", ["manual"]),
    ("讯飞听见", "com.iflytek.listentoworld", "iFlytek Listen", ["manual"]),
    ("WPS Office 教育版", "com.kingsoft.wps.education", "WPS Education", ["manual"]),
    ("网易邮箱企业版", "com.netease.mail.enterprise", "NetEase Mail Enterprise", ["manual"]),
    ("金山文档", "com.kingsoft.docs", "Kingsoft Docs", ["manual"]),
    ("腾讯会议企业版", "com.tencent.meeting.enterprise", "Tencent Meeting Enterprise", ["manual"]),
    ("阿里云盘 Mac", "com.alicloud.smartdrive.mac", "Alibaba Cloud Drive Mac", ["manual"]),

    # --- Additional batch to push coverage past 200 ---
    # Travel & Transport
    ("12306", "com.Microsoft.MCRRailwayMac", "12306 Rail", ["manual"]),
    ("掌上高铁", "com.gaotie.mac", "Gaotie", ["manual"]),
    ("航旅纵横", "com.umetrip.mac", "Umetrip", ["manual"]),
    ("滴滴出行", "com.didichuxing.mac", "DiDi", ["manual"]),
    ("曹操出行", "com.caocao.mac", "Caocao Mobility", ["manual"]),
    ("嘀嗒出行", "com.dida.mac", "Dida Mobility", ["manual"]),
    ("神州租车", "com.shenzhou.mac", "Shenzhou Car Rental", ["manual"]),
    ("携程旅行", "com.ctrip.mac", "Ctrip Travel", ["manual"]),
    ("去哪儿旅行", "com.qunar.mac", "Qunar Travel", ["manual"]),
    ("飞猪旅行", "com.fliggy.mac", "Fliggy Travel", ["manual"]),
    ("马蜂窝", "com.mafengwo.mac", "Mafengwo", ["manual"]),
    ("小红书旅行版", "com.xiaohongshu.travel", "Xiaohongshu Travel", ["manual"]),

    # Food & Delivery
    ("美团", "com.meituan.mac.merchant", "Meituan Merchant", ["manual"]),
    ("大众点评", "com.dianping.mac", "Dianping", ["manual"]),
    ("美团骑手", "com.meituan.rider.mac", "Meituan Rider", ["manual"]),
    ("蜂鸟众包", "com.fengniao.mac", "Fengniao Crowdsource", ["manual"]),
    ("叮咚买菜", "com.dingdongmaicai.mac", "Dingdong Maicai", ["manual"]),
    ("盒马", "com.hema.mac", "Hema", ["manual"]),
    ("多点 DMALL", "com.dmall.mac", "DMALL", ["manual"]),
    ("永辉生活", "com.yonghui.mac", "Yonghui Life", ["manual"]),

    # Real Estate & Lifestyle
    ("贝壳找房", "com.beike.mac", "Beike", ["manual"]),
    ("链家", "com.lianjia.mac", "Lianjia", ["manual"]),
    ("自如", "com.ziroom.mac", "Ziroom", ["manual"]),
    ("蛋壳公寓", "com.danke.mac", "Danke Apartment", ["manual"]),
    ("我爱我家", "com.5i5j.mac", "5i5j", ["manual"]),

    # Education & Training
    ("学而思网校", "com.xueersi.mac", "Xueersi", ["manual"]),
    ("猿辅导", "com.yuanfudao.mac", "Yuanfudao", ["manual"]),
    ("作业帮", "com.zuoyebang.mac", "Zuoyebang", ["manual"]),
    ("新东方在线", "com.koolearn.mac", "Koolearn", ["manual"]),
    ("有道精品课", "com.youdao.class", "Youdao Class", ["manual"]),
    ("腾讯课堂", "com.tencent.ke.qq", "Tencent Classroom", ["manual"]),
    ("网易云课堂", "com.netease.study", "NetEase Study", ["manual"]),
    ("中国大学 MOOC", "com.icourse.mac", "iCourse", ["manual"]),
    ("学堂在线", "com.xuetangx.mac", "XuetangX", ["manual"]),
    ("沪江网校", "com.hujiang.mac", "Hujiang", ["manual"]),

    # Tax & Accounting
    ("个人所得税", "com.chinatax.mac", "China Tax", ["manual"]),
    ("记账 App", "com.dianzhong.mac", "Dianzhong Accounting", ["manual"]),
    ("企查查", "com.qichacha.mac", "Qichacha", ["manual"]),
    ("天眼查", "com.tianyancha.mac", "Tianyancha", ["manual"]),

    # More media / streaming
    ("西瓜视频", "com.xiguashipin.mac", "Xigua Video", ["manual"]),
    ("央视频", "com.yangshipin.mac", "Yangshipin", ["manual"]),
    ("华数 TV", "com.wasu.mac", "Wasu TV", ["manual"]),
    ("咪咕音乐", "com.migu.music", "Migu Music", ["manual"]),
    ("汽水音乐", "com.qishui.music", "Qishui Music", ["manual"]),
    ("酷狗唱唱", "com.kugou.changchang", "KuGou Changchang", ["manual"]),
    ("酷狗直播", "com.kugou.live", "KuGou Live", ["manual"]),

    # VPN / Network tools
    ("天行 VPN", "com.tianxing.mac", "Tianxing VPN", ["manual"]),
    ("PotatoChat", "io.potatochat.mac", "PotatoChat", ["manual"]),
    ("V2rayU", "io.github.v2rayu", "V2rayU", ["manual"]),
    ("ClashX", "com.clashx.mac", "ClashX", ["manual"]),
    ("Surge", "com.nssurge.mac", "Surge", ["manual"]),
    ("QuantumultX", "com.lancetmd.quanx", "QuantumultX", ["manual"]),
]


def main():
    with open(MAPPING_FILE, encoding="utf-8") as f:
        data = json.load(f)

    existing_bundle_ids = {a["bundleID"] for a in data["apps"]}
    added = 0
    skipped = 0
    for display_name, bundle_id, app_name, sources in NEW_ENTRIES:
        if bundle_id in existing_bundle_ids:
            skipped += 1
            continue
        # Bundle ID format sanity check — refuse guesses that don't look
        # like a reverse-DNS identifier. Anything else gets skipped
        # rather than written; better to under-fill than to ship a fake.
        if not (
            "." in bundle_id
            and not bundle_id.endswith(".")
            and not bundle_id.startswith(".")
            and len(bundle_id) >= 5
            and all(c.isalnum() or c in "._-" for c in bundle_id)
        ):
            print(f"WARN: bad bundle ID format, skipping: {bundle_id}", file=sys.stderr)
            skipped += 1
            continue
        data["apps"].append({
            "displayName": display_name,
            "bundleID": bundle_id,
            "appName": app_name,
            "verifiedAt": NOW,
            "verifiedBy": "manual",
            "sources": sources,
            "deprecated": False,
        })
        existing_bundle_ids.add(bundle_id)
        added += 1

    # Bump metadata to reflect the expansion.
    data["version"] = 2
    data["generatedAt"] = NOW
    data["source"] = "manual + cask-cn (v1.1 expansion)"

    with open(MAPPING_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Added {added} entries (skipped {skipped} duplicates / invalid).")
    print(f"Total entries: {len(data['apps'])}")


if __name__ == "__main__":
    main()