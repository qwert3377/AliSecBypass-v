//
//  SideStore 运行时汉化 —— TrollStore 注入单文件
//  无 Logos 语法，纯 ObjC Runtime + MSHookFunction，MRC
//  翻译表内嵌；CoreText 原生替换 + 排版缓存；CFString/CFBundle 生成端兜底
//
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <unordered_map>
#include <string>
#include <cctype>

#pragma clang diagnostic ignored "-Wundeclared-selector"

// ===================== 翻译表（内嵌，共 480 条）=====================
static const char *kTable[][2] = {
    {"Developer Options", "开发者选项"},
    {"LOGGING & DIAGNOSTICS", "日志与诊断"},
    {"Disable URL Response Caching", "禁用URL响应缓存"},
    {"Rotate Logs on Startup", "启动时轮转日志"},
    {"SideStore Verbose Logging", "SideStore详细日志"},
    {"Widget Verbose Logging", "Widget详细日志"},
    {"SideSign Verbose Logging", "SideSign详细日志"},
    {"Minimuxer Verbose Logging", "Minimuxer详细日志"},
    {"Operations Verbose Logging", "Operations详细日志"},
    {"Operations Logging Control", "Operations日志控制"},
    {"WIDGET OPTIONS", "Widget选项"},
    {"Reload All Widgets", "重载所有Widget"},
    {"Rotate Widget Log", "轮转Widget日志"},
    {"Export Database", "导出数据库"},
    {"Import Database", "导入数据库"},
    {"DATABASE OPTIONS", "Database选项"},
    {"APPEARANCE & THEMES", "外观与主题"},
    {"Theme Manager", "主题管理"},
    {"ANISETTE", "ANISETTE"},
    {"On-Device Anisette", "设备端Anisette"},
    {"Run ADI emulation directly on device instead of remote servers", "在设备上直接运行ADI仿真，代替远程服务器"},
    {"Anisette Client Configuration", "Anisette客户端配置"},
    {"Reset adi.pb", "重置adi.pb"},
    {"Clear local Anisette provisioning data from Keychain", "从钥匙串清除本地Anisette预置数据"},
    {"SideSign Client Configuration", "SideSign客户端配置"},
    {"GENERAL", "通用"},
    {"Customize AppID", "定制AppID"},
    {"Customize App Extensions", "定制应用扩展"},
    {"Auto-Fix AppGroup IDs", "自动修复组ID"},
    {"Required for free developer accounts", "免费开发者账户需要"},
    {"Prefer Resigned IPA", "优先重签IPA"},
    {"Prefer IPA (speed) vs App (storage) efficiency", "IPA(速度)与App(存储)效率优先"},
    {"BETA TESTING", "Beta测试"},
    {"Opt in for beta testing to receive regular updates and early previews of upcoming releases.", "加入Beta测试，定期接收更新和即将发布版本的抢先预览。"},
    {"Please note that these builds are experimental and may be unstable or break unexpectedly.", "请注意，这些构建为实验版本，可能不稳定或出现意外问题。"},
    {"ADVANCED SETTINGS", "高级设置"},
    {"Are you sure to reset the pairing file?", "确定要重置配对文件吗？"},
    {"You can reset the pairing file when you cannot sideload apps or enable JIT. You need to restart SideStore.", "当无法侧载应用或启用JIT时，可重置配对文件。重置后需重启SideStore。"},
    {"Delete and Reset", "删除并重置"},
    {"Cancel", "取消"},
    {"DEVELOPER ACCOUNT", "开发者账户"},
    {"App IDs", "App ID"},
    {"registered", "已注册"},
    {"Provisioning Profiles", "描述文件"},
    {"active on portal", "门户中生效"},
    {"Certificates", "证书"},
    {"App Groups", "应用组"},
    {"configured", "已配置"},
    {"Registered Devices", "已注册设备"},
    {"User Customizations", "用户自定义"},
    {"Connection Config", "连接配置"},
    {"SideSign", "SideSign"},
    {"Are you sure you want to clear all existing refresh attempt entries?", "确定要清除所有刷新记录吗？"},
    {"Are you sure you want to clear the error log?", "确定要清除错误日志吗？"},
    {"Are you sure you want to deactivate the active signing certificate locally?", "确定要在本地停用当前签名证书吗？"},
    {"Are you sure you want to delete the backup for this app? This action cannot be undone.", "确定要删除此应用的备份吗？此操作无法撤销。"},
    {"Are you sure you want to delete this certificate locally? This will remove it from the cached local store.", "确定要在本地删除此证书吗？这将把它从本地缓存存储中移除。"},
    {"Are you sure you want to restore this backup?", "确定要恢复此备份吗？"},
    {"Are you sure you want to revoke this certificate? This will permanently delete the certificate on Apple's servers.", "确定要吊销此证书吗？这将从Apple服务器上永久删除它。"},
    {"Are you sure you want to sign out? You will no longer be able to install or refresh apps once you sign out.", "确定要退出登录吗？退出后将无法再安装或刷新应用。"},
    {"Do you want to clear all keychain items related to this SideStore instance?", "要清除与此SideStore实例相关的所有钥匙串项目吗？"},
    {"Do you want to export your certificate to an external app? That app will be able to sign apps using your certificate.", "要将证书导出到外部应用吗？该应用将能使用您的证书为应用签名。"},
    {"Did you move to different screen or background after starting the operation?", "开始操作后您是否切换了屏幕或退到后台？"},
    {"Are you sure you want to delete all data for", "确定要删除其所有数据吗"},
    {"Are you sure you want to delete", "确定要删除吗"},
    {"1 App ID Remaining", "剩1个App ID"},
    {"Failed to Refresh Apps", "刷新应用失败"},
    {"Failed to Resign SideStore", "重签SideStore失败"},
    {"Failed to Clear Error Log", "清除日志失败"},
    {"Certificate deleted locally.", "证书已从本地删除。"},
    {"Failed to fetch App IDs. ", "获取App ID失败。"},
    {"Backup imported successfully to: ", "备份已成功导入到："},
    {"An error occurred while installing the app.", "安装应用时发生错误。"},
    {"An unknown error occurred.", "发生未知错误。"},
    {"An unknown error occurred during signing.", "签名时发生未知错误。"},
    {"An expired certificate was detected.", "检测到已过期的证书。"},
    {"An error occurred during pairing.", "配对时发生错误。"},
    {"An error occurred while clearing the cache: ", "清除缓存时发生错误："},
    {"An error occurred while using SideJIT: ", "使用SideJIT时发生错误："},
    {"Authentication failed", "认证失败"},
    {"Authentication handshake failed: ", "认证握手失败："},
    {"Apple's servers took too long to respond (connection timed out).", "Apple服务器响应超时。"},
    {"A connection to AltServer could not be established.", "无法建立与AltServer的连接。"},
    {"AltServer could not establish a connection to SideStore.", "AltServer无法连接到SideStore。"},
    {"A source cannot change its identifier once added. This source can no longer be updated.", "软件源添加后无法更改其标识符，此软件源将无法再更新。"},
    {"Any apps you've installed from this source will remain, but they'll no longer receive any app updates.", "从此软件源安装的应用会保留，但不再接收应用更新。"},
    {"App IDs for paid developer accounts never expire, and there is no limit to how many you can create.", "付费开发者账户的App ID永不过期，且创建数量没有限制。"},
    {"Delete sideloaded apps to free up App ID slots.", "删除侧载应用以释放App ID名额。"},
    {"All configured Anisette servers failed to respond with valid Anisette data.", "所有Anisette服务器均未返回有效数据。"},
    {"A network failure occurred.", "发生网络故障。"},
    {"A device failure has occurred.", "发生设备故障。"},
    {"A cryptographic verification failure has occurred.", "发生加密验证失败。"},
    {"A verification failure occurred.", "发生验证失败。"},
    {"A callback has failed.", "回调失败。"},
    {"A function has failed.", "函数调用失败。"},
    {"An internal error occurred in the Security framework.", "安全框架发生内部错误。"},
    {"A MobileMe server error occurred.", "MobileMe服务器出错。"},
    {"A MobileMe service error has occurred.", "MobileMe服务出错。"},
    {"A MobileMe CSR verification failure has occurred.", "MobileMe CSR验证失败。"},
    {"A device verification failure has occurred.", "设备验证失败。"},
    {"Adding an application ACL subject failed.", "添加应用ACL主体失败。"},
    {"An ACL add operation has failed.", "ACL添加操作失败。"},
    {"An ACL change operation has failed.", "ACL更改操作失败。"},
    {"An ACL delete operation has failed.", "ACL删除操作失败。"},
    {"An ACL replace operation has failed.", "ACL替换操作失败。"},
    {"A module failed to initialize.", "模块初始化失败。"},
    {"A module manifest verification failure has occurred.", "模块清单验证失败。"},
    {"A verify action has failed.", "验证操作失败。"},
    {"Connect to Target Device", "连接到目标设备"},
    {"Connection Configuration", "连接配置"},
    {"Connection Details", "连接详情"},
    {"Connecting to device...", "正在连接设备…"},
    {"Connecting to Developer Portal...", "正在连接开发者门户…"},
    {"Connect to a Wi-Fi network, Bridge or a Wired network connection!", "请连接Wi-Fi、网桥或有线网络！"},
    {"Ensure both devices are on the same Wi-Fi network.", "请确保两台设备在同一Wi-Fi网络。"},
    {"Ensure both devices are on the same Wi-Fi.", "确保两台设备在同一Wi-Fi。"},
    {"Enter the pairing code shown below on your other device settings screen.", "请在另一台设备的设置屏幕中输入下方显示的配对码。"},
    {"Enter the password used to encrypt this backup file.", "输入用于加密此备份文件的密码。"},
    {"Device rejected pairing verify handshake: ", "设备拒绝了配对验证握手："},
    {"Connection closed by peer", "连接被对端关闭"},
    {"Connection reset by peer", "连接被对端重置"},
    {"Connection failed: ", "连接失败："},
    {"Could not connect to SideStore.", "无法连接到SideStore。"},
    {"Could not decode Permissions.plist.", "无法解码Permissions.plist。"},
    {"Could not decode file as a property list.", "无法将文件解码为属性列表。"},
    {"Could not find device", "未找到设备"},
    {"Could not find profile", "未找到描述文件"},
    {"Could not load image", "无法加载图片"},
    {"Could not refresh store.", "无法刷新商店。"},
    {"Code signing failed: ", "代码签名失败："},
    {"Decryption failed: ", "解密失败："},
    {"Encryption payload failed.", "加密负载失败。"},
    {"Database Delete Scheduled on Next Launch", "已安排下次启动时删除数据库"},
    {"Deleting the database will remove all app entries and sources from SideStore.", "删除数据库将移除所有应用条目和软件源。"},
    {"Failed to find Pairing File!", "未找到配对文件！"},
    {"Failed to generate pairing file", "生成配对文件失败"},
    {"Failed to copy SideStore app bundle to its proper location.", "无法将SideStore应用包复制到正确位置。"},
    {"Failed to install IPA, error: ", "安装IPA失败，错误："},
    {"Failed to delete app: ", "删除应用失败："},
    {"Failed to delete backup for ", "删除备份失败："},
    {"Failed to back up app: ", "备份应用失败："},
    {"Failed to fetch app icon from ", "获取应用图标失败："},
    {"Failed to fetch source icon from ", "获取软件源图标失败："},
    {"Failed to fetch server list: ", "获取服务器列表失败"},
    {"Failed to fetch catalog from '", "获取目录失败："},
    {"Failed to fetch categories. ", "获取分类失败。"},
    {"Failed to fetch Apple WWDR intermediate certificate.", "获取Apple WWDR中间证书失败。"},
    {"Failed to connect to device: ", "连接设备失败："},
    {"Failed to activate app: ", "激活应用失败："},
    {"Failed to deactivate app: ", "停用应用失败："},
    {"Failed to apply filter: ", "应用过滤器失败："},
    {"Failed to import file: ", "导入文件失败："},
    {"Failed to list directory contents.", "列出目录内容失败。"},
    {"Failed to encode pairingFile!", "编码配对文件失败！"},
    {"Failed to determine if source is added. ", "无法确定软件源是否已添加。"},
    {"Available Servers (OFFLINE)", "可用服务器（离线）"},
    {"App Backups Directory", "应用备份目录"},
    {"Error: Backup directory URL not found.", "错误：未找到备份目录URL。"},
    {"Exports SideStore.conf to import into WireGuard VPN app", "导出SideStore.conf以导入WireGuard VPN应用"},
    {"All requirements met. Local device pairing & Remote server connection active.", "所有条件已满足。本地配对和远程连接均已激活。"},
    {"All requirements met. Local device pairing & VPN tunnel active.", "所有条件已满足。本地配对和VPN隧道已激活。"},
    {" to complete sign-in.", " 以完成登录。"},
    {". Please try again. If the issue persists, report it on GitHub Issues!", "。请重试。若问题依旧请在GitHub反馈！"},
    {"Delete Certificate", "删除证书"},
    {"Each app and app extension installed with SideStore must register an App ID with Apple. Apple limits non-developer Apple IDs to 10 App IDs at a time.\n\n**App IDs can't be deleted**, but they do expire after one week. SideStore will automatically renew App IDs for all active apps once they've expired.", "SideStore安装的每个应用和应用扩展都必须向Apple注册App ID。Apple限制非开发者Apple ID同时最多10个App ID。\n\n**App ID无法删除**，但会在一周后过期。过期后SideStore会自动为所有活跃应用续期。"},
    {"Select the certificate type and machine name. This registers the certificate on Apple's servers and saves the private key locally.", "请选择证书类型和机器名称。这会在Apple服务器上注册证书并在本地保存私钥。"},
    {"To ensure you can continue using SideStore, \nthe app must be reinstalled now using the new certificate. Otherwise, you will be unable to refresh or open SideStore once the old certificate expires.", "为了您能继续使用SideStore，\n现在必须使用新证书重新安装本应用。否则，旧证书过期后您将无法刷新或打开SideStore。"},
    {"RemoveAppExtensionsOperation: unable to present dialog, view context not available.\nDid you move to different screen or background after starting the operation?", "RemoveAppExtensionsOperation：无法显示对话框，视图上下文不可用。\n开始操作后您是否切换了屏幕或退到后台？"},
    {"Not After", "失效期"},
    {"Not Before", "生效期"},
    {"Serial Number", "序列号"},
    {"Validity", "有效"},
    {"Subject", "主体"},
    {"Source", "来源"},
    {"Installing", "安装中"},
    {"Installed", "已安装"},
    {"Updating", "更新"},
    {"Refreshing", "刷新中"},
    {"Sideloading", "侧载中"},
    {"Deleting", "删除"},
    {"Backing Up", "备份中"},
    {"Restoring", "恢复中"},
    {"Downloading", "下载中"},
    {"Preparing", "准备中"},
    {"Compressing", "压缩中"},
    {"Signing", "签名"},
    {"Processing", "处理中"},
    {"Loading", "加载"},
    {"Refresh", "刷新"},
    {"Delete", "删除"},
    {"Continue", "继续"},
    {"Enable", "启用"},
    {"Disable", "禁用"},
    {"Choose", "选择"},
    {"Import", "导入"},
    {"Export", "导出"},
    {"Done", "完成"},
    {"Save", "保存"},
    {"Close", "关闭"},
    {"Back", "返回"},
    {"Edit", "编辑"},
    {"Add", "添加"},
    {"Remove", "移除"},
    {"View", "查看"},
    {"Copy", "复制"},
    {"Copied", "已复制"},
    {"Paste", "粘贴"},
    {"Next", "下一步"},
    {"Skip", "跳过"},
    {"Finish", "完成"},
    {"Confirm", "确认"},
    {"Reset", "重置"},
    {"Clear", "清除"},
    {"Search", "搜索"},
    {"Select", "选择"},
    {"Keep", "保留"},
    {"Get Started", "开始使用"},
    {"Not Now", "暂不"},
    {"Learn More", "了解更多"},
    {"Got it", "知道了"},
    {"Try Again", "重试"},
    {"OPEN", "打开"},
    {"UPDATE", "更新"},
    {"INSTALL", "安装"},
    {"DELETE", "删除"},
    {"REMOVE", "移除"},
    {"BACKUP", "备份"},
    {"RESTORE", "恢复"},
    {"REFRESH", "刷新"},
    {"Delete App", "删除应用"},
    {"Remove App", "移除应用"},
    {"Update App", "更新应用"},
    {"Developer", "开发者"},
    {"Version", "版本"},
    {"Size", "大小"},
    {"Released", "发布日期"},
    {"Minimum iOS Version", "最低iOS版本"},
    {"Unsupported", "不支持"},
    {"Untrusted", "未信任"},
    {"Unknown", "未知"},
    {"Incompatible", "不兼容"},
    {"Outdated", "已过时"},
    {"Offline", "离线"},
    {"Online", "在线"},
    {"Unavailable", "不可用"},
    {"Available", "可用"},
    {"Expired", "已过期"},
    {"Active", "使用中"},
    {"Stale", "已过期"},
    {"Blocked", "已阻止"},
    {"No apps installed.", "尚未安装应用。"},
    {"App is already installed.", "应用已安装。"},
    {"App not found.", "未找到应用。"},
    {"No Updates Available", "暂无可用更新"},
    {"Refresh All", "全部刷新"},
    {"Refresh Attempts", "刷新记录"},
    {"Last refreshed", "上次刷新"},
    {"Never", "从未"},
    {"Just now", "刚刚"},
    {"minutes ago", "分钟前"},
    {"hours ago", "小时前"},
    {"days ago", "天前"},
    {"Up to Date", "已是最新"},
    {"Account", "账户"},
    {"Sign In", "登录"},
    {"Sign Out", "退出登录"},
    {"Select a Team", "选择团队"},
    {"Team", "团队"},
    {"Developer Mode", "开发者模式"},
    {"Enable Developer Mode", "启用开发者模式"},
    {"2FA verification error", "两步验证错误"},
    {"Add Custom Certificate ID", "添加自定义证书ID"},
    {"Add Custom Device ID / UDID", "添加设备ID/UDID"},
    {"Developer Portal Services", "开发者门户服务"},
    {"Disable Device", "停用设备"},
    {"Enable Device", "启用设备"},
    {"Remove App ID", "移除App ID"},
    {"Name", "名称"},
    {"Date", "日期"},
    {"Type", "类型"},
    {"Description", "描述"},
    {"Version Notes", "版本说明"},
    {"Device IP", "设备IP"},
    {"RemotePair Port", "配对端口"},
    {"Anisette Server", "Anisette服务器"},
    {"Add Server", "添加服务器"},
    {"Advanced Settings", "高级设置"},
    {"Disable App Limit", "禁用应用数量限制"},
    {"Disable Idle Timeout", "禁用闲置超时"},
    {"Enable Beta Updates", "启用Beta更新"},
    {"Beta Updates Track", "Beta更新通道"},
    {"Clear Data Cache", "清除数据缓存"},
    {"Clear Cache", "清除缓存"},
    {"Reset Pairing File", "重置配对文件"},
    {"View Error Log", "查看错误日志"},
    {"Error Log", "错误日志"},
    {"Error Code", "错误代码"},
    {"Error Description", "错误描述"},
    {"Software Licenses", "软件许可"},
    {"Instructions", "使用指南"},
    {"Send Feedback", "发送反馈"},
    {"Storage Explorer", "存储空间浏览器"},
    {"Health Check", "健康检查"},
    {"Change App Icon", "更改应用图标"},
    {"Website", "网站"},
    {"More", "更多"},
    {"About", "关于"},
    {"Credits", "鸣谢"},
    {"Default", "默认"},
    {"None", "无"},
    {"Enable LocalDevVPN", "启用LocalDevVPN"},
    {"Sideload App", "侧载应用"},
    {"Choose an App", "选择应用"},
    {"Select an App", "选择应用"},
    {"Choose File", "选择文件"},
    {"Sideloading...", "侧载中…"},
    {"Sideloaded successfully!", "侧载成功！"},
    {"Failed to sideload app.", "应用侧载失败。"},
    {"Open Settings", "打开设置"},
    {"has expired.", "已过期。"},
    {"will expire in", "将在"},
    {"days.", "天后过期。"},
    {"Refresh in Settings", "在设置中刷新"},
    {"Add Source", "添加软件源"},
    {"Import Source", "导入软件源"},
    {"Enter source URL", "输入软件源URL"},
    {"Source not found.", "未找到软件源。"},
    {"Invalid URL", "URL无效"},
    {"Invalid source URL.", "软件源URL无效。"},
    {"Source already added.", "软件源已添加。"},
    {"Failed to add source.", "添加软件源失败。"},
    {"Source removed.", "软件源已移除。"},
    {"Refresh Sources", "刷新软件源"},
    {"Refreshing sources...", "刷新软件源中…"},
    {"No sources added yet.", "未添加软件源。"},
    {"No results", "无结果"},
    {"No results found.", "未找到结果。"},
    {"Backup", "备份"},
    {"Backup imported successfully.", "备份导入成功。"},
    {"Backup failed.", "备份失败。"},
    {"Restore failed.", "恢复失败。"},
    {"Export Backup", "导出备份"},
    {"Import Backup", "导入备份"},
    {"Are you sure you want to delete this backup?", "确定要删除此备份吗？"},
    {"This action cannot be undone.", "此操作无法撤销。"},
    {"This will also delete all app data.", "这将同时删除所有应用数据。"},
    {"Remove from SideStore?", "从SideStore移除？"},
    {"Error", "错误"},
    {"Success", "成功"},
    {"Failure", "失败"},
    {"Unknown Error", "未知错误"},
    {"Network Error", "网络错误"},
    {"Server Error", "服务器错误"},
    {"Connection Error", "连接错误"},
    {"Connection Failed", "连接失败"},
    {"Connection Timed Out", "连接超时"},
    {"No Internet Connection", "无网络连接"},
    {"Please check your internet connection.", "请检查网络连接。"},
    {"Try again later.", "请稍后重试。"},
    {"Something went wrong.", "出现问题。"},
    {"An error occurred.", "发生错误。"},
    {"Unable to connect.", "无法连接。"},
    {"Unable to install app.", "无法安装应用。"},
    {"Unable to refresh app.", "无法刷新应用。"},
    {"Unable to delete app.", "无法删除应用。"},
    {"Unable to backup app.", "无法备份应用。"},
    {"Unable to restore app.", "无法恢复应用。"},
    {"device rejected handshake. Please redo pairing.", "设备拒绝了握手，请重新配对。"},
    {"LocalDevVPN is not connected", "LocalDevVPN未连接"},
    {"Developer Account", "开发者账户"},
    {"Logging & Diagnostics", "日志与诊断"},
    {"Widget Options", "Widget选项"},
    {"Database Options", "Database选项"},
    {"Beta Testing", "Beta测试"},
    {"Appearance & Themes", "外观与主题"},
    {"News", "新闻"},
    {"Browse", "浏览"},
    {"Settings", "设置"},
    {"Sources", "软件源"},
    {"Updates", "更新"},
    {"My Apps", "我的应用"},
    {"All Apps", "全部应用"},
    {"All News", "全部新闻"},
    {"Featured", "精选"},
    {"FREE", "免费"},
    {"Free", "免费"},
    {"See All", "查看全部"},
    {"Categories", "分类"},
    {"Less", "收起"},
    {"New & Updated", "最新与更新"},
    {"Expires in", "剩余有效期"},
    {"View App IDs", "查看App ID"},
    {"Support the team", "支持开发团队"},
    {"Email", "电子邮件"},
    {"Other", "其他"},
    {"Support the SideStore Team by following our socials or becoming a patron!", "关注我们的社交媒体或成为赞助者，支持SideStore团队！"},
    {"SideStore Offical", "SideStore官方源"},
    {"SideStore Team", "SideStore团队"},
    {"Starting.", "正在启动…"},
    {"Loading apps.", "正在加载应用…"},
    {"Updating sources.", "正在更新软件源…"},
    {"Almost there.", "就快好了…"},
    {"Almost there..", "就快好了…"},
    {"Almost there...", "就快好了…"},
    {"Loading...", "加载中…"},
    {"Check out the Documentation for more info", "查看文档了解更多信息"},
    {"SideStore is currently pre-release software. Expect bugs, and please report them", "SideStore目前为预发布软件，可能存在bug，欢迎向我们反馈"},
    {"Error 0xe8008024 / 0xe8008018", "错误 0xe8008024 / 0xe8008018"},
    {"Free Developer Account", "免费开发者账户"},
    {"DIAGNOSTICS", "诊断"},
    {"SUPPORT US", "支持我们"},
    {"Display", "显示"},
    {"Personalize your SideStore experience by choosing an alternate app icon.", "通过选择备用应用图标，个性化您的SideStore"},
    {"No Errors", "无错误"},
    {"Errors that occur when sideloading or refreshing apps will appear here.", "侧载或刷新应用时出现的错误将显示在这里"},
    {"Today", "今天"},
    {"Refresh SideStore Failed", "刷新SideStore失败"},
    {"Send Email", "发送邮件"},
    {"No Refresh Attempts", "暂无刷新记录"},
    {"Clear Data Cache...", "清除数据缓存…"},
    {"Developers", "开发者"},
    {"UI Designer", "界面设计"},
    {"Asset Designer", "美术设计"},
    {"Licenses", "开源许可"},
    {"REFRESHING APPS", "正在刷新应用"},
    {"TECHY THINGS", "技术内容"},
    {"CREDITS", "鸣谢"},
    {"View Recommended Sources", "查看推荐软件源"},
    {"ACTIVATE", "激活"},
    {"INACTIVE", "未激活"},
    {"Sideloaded", "已侧载"},
    {"Developer Portal", "开发者门户"},
    {"Portal Services", "门户服务"},
    {"Welcome to SideStore!", "欢迎使用SideStore！"},
    {"Proceed with Caution!", "谨慎操作！"},
    {"We are aware of the issue and actively investigating it!", "我们已知晓该问题并正在积极调查！"},
    {"A new version has released with new stability improvements, tap for more info!", "新版本已发布，包含稳定性改进，点击查看详情！"},
    {"Welcome to SideStore", "欢迎使用SideStore"},
    {"Starting…", "正在启动…"},
    {"Loading apps…", "正在加载应用…"},
    {"Updating sources…", "正在更新软件源…"},
    {"Almost there…", "就快好了…"},
    {"SideStore Expiring Soon", "SideStore即将过期"},
    {"SideStore will expire in 24 hours. Open the app and refresh it to prevent it from expiring.", "SideStore将在24小时后过期。请打开应用并刷新以防止过期。"},
    {"SideStore Expiring Extremely Soon", "SideStore马上就要过期了"},
    {"SideStore will expire in 6 hours! Refresh now to prevent expiration.", "SideStore将在6小时后过期！请立即刷新以防止过期。"},
    {"SideStore Expired", "SideStore已过期"},
    {"SideStore has expired. Please refresh or reinstall the app.", "SideStore已过期。请刷新或重新安装应用。"},
    {"⚠️A new version has released with new stability improvements, tap for more info!", "⚠️新版本已发布，包含稳定性改进，点击查看详情！"},
    {"Enable SideJITServer", "启用SideJITServer"},
    {"Required for JIT on iOS 17+", "iOS 17+使用JIT所需"},
    {"Test Connection (Ping)", "测试连接（Ping）"},
    {"Leave empty to automatically discover SideJITServer on your local network via Bonjour.", "留空以通过Bonjour在本地网络自动发现SideJITServer。"},
    {"Prompt AppExtns Customization", "提示应用扩展定制"},
    {"Sign in with Apple ID", "使用Apple ID登录"},
    {"Side Team", "Side团队"},
    {"Background Refresh", "后台刷新"},
    {"Allow Siri To Refresh Apps…", "允许Siri刷新应用…"},
    {"How it works", "工作原理"},
    {"Anisette Servers", "Anisette服务器"},
    {"Certificate Management", "证书管理"},
    {"Backup & Restore", "备份与恢复"},
    {"Experimental Features", "实验性功能"},
    {"Follow SideStore for updates", "关注SideStore获取最新动态"},
    {"Clear Data Cache…", "清除数据缓存…"},
    {"SideJITServer", "SideJIT服务器"},
    {"STANDALONE FEATURES", "独立功能"},
    {"FEATURE FLAGS", "功能开关"},
    {"Cache Management", "缓存管理"},
    {"Network Discovery", "网络发现"},
    {"Cellular Refresh", "蜂窝网络刷新"},
    {"View Refresh Attempts", "查看刷新记录"},
    {"Unable to Refresh “%@” Source", "无法刷新“%@”软件源"},
    {"Failed to refresh Store", "刷新商店失败"},
    {"Some sources were unable to load", "部分软件源无法加载"},
    {"Unable to Fetch News", "无法获取新闻"},
    {"The request timed out.", "请求超时。"},
    {"Enable Background Refresh to automatically refresh apps in the background when connected to Wi-Fi.", "连接Wi-Fi时在后台自动刷新应用。"},
    {"Enable Disable Idle Timeout to allow SideStore to keep your device awake during a refresh or install of any apps.", "启用禁用闲置超时，让SideStore在刷新或安装应用期间保持设备不休眠。"},
    {"Free up disk space by removing non-essential data, such as temporary files and backups for uninstalled apps.", "通过移除非必要数据（如临时文件和已卸载应用的备份）释放磁盘空间。"},
};

static std::unordered_map<std::string, std::string> &TABLE() {
    static std::unordered_map<std::string, std::string> *m = nullptr;
    if (!m) {
        m = new std::unordered_map<std::string, std::string>();
        for (auto &p : kTable) (*m)[p[0]] = p[1];
    }
    return *m;
}
// 小写兜底表（只收第一个）
static std::unordered_map<std::string, std::string> &TABLE_LOWER() {
    static std::unordered_map<std::string, std::string> *m = nullptr;
    if (!m) {
        m = new std::unordered_map<std::string, std::string>();
        for (auto &p : kTable) {
            std::string lo(p[0]);
            for (auto &c : lo) c = (char)tolower((unsigned char)c);
            if (!m->count(lo)) (*m)[lo] = p[1];
        }
    }
    return *m;
}
// 非字母数字折叠兜底表
static std::unordered_map<std::string, std::string> &TABLE_FOLD() {
    static std::unordered_map<std::string, std::string> *m = nullptr;
    if (!m) {
        m = new std::unordered_map<std::string, std::string>();
        for (auto &p : kTable) {
            std::string f;
            for (const char *c = p[0]; *c; ++c) if (isalnum((unsigned char)*c)) f += (char)tolower((unsigned char)*c);
            if (!m->count(f)) (*m)[f] = p[1];
        }
    }
    return *m;
}

// ===================== 查表（返回 nil 或中文 NSString）=====================
static NSString *cn(NSString *s) {
    if (!s || (id)s == (id)[NSNull null]) return nil;
    NSUInteger len = [s length];
    if (len < 2 || len > 480) return nil;
    unichar c0 = [s characterAtIndex:0];
    if (!((c0 >= 'A' && c0 <= 'Z') || (c0 >= 'a' && c0 <= 'z'))) return nil;
    std::string k([s UTF8String]);
    if (k.size() < 2) return nil;
    auto &t = TABLE();
    auto it = t.find(k);
    if (it == t.end()) {
        std::string lo(k);
        for (auto &c : lo) c = (char)tolower((unsigned char)c);
        it = TABLE_LOWER().find(lo);
        if (it == TABLE_LOWER().end()) {
            std::string f;
            for (auto c : lo) if (isalnum((unsigned char)c)) f += c;
            auto it2 = TABLE_FOLD().find(f);
            if (it2 == TABLE_FOLD().end()) return nil;
            return [NSString stringWithUTF8String:it2->second.c_str()];
        }
    }
    return [NSString stringWithUTF8String:it->second.c_str()];
}

// ===================== swizzle 工具 =====================
static void swz(const char *clsName, const char *selName, IMP imp, IMP *outOld) {
    Class c = objc_getClass(clsName);
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(selName));
    if (!m) return;
    *outOld = method_getImplementation(m);
    method_setImplementation(m, imp);
}
static void swzClassMethod(const char *clsName, const char *selName, IMP imp, IMP *outOld) {
    Class c = objc_getClass(clsName);
    if (!c) return;
    Class meta = object_getClass(c);
    Method m = class_getInstanceMethod(meta, sel_registerName(selName));
    if (!m) return;
    *outOld = method_getImplementation(m);
    method_setImplementation(m, imp);
}

// ===================== UIKit 生成端 swizzle（原生，零 JS 开销）=====================
#define DEF_SWZ1(C, S, T) \
static void (*orig_##C##_##S)(id, SEL, T); \
static void hook_##C##_##S(id self, SEL _cmd, T v) { orig_##C##_##S(self, _cmd, cn((NSString *)v) ?: v); }

DEF_SWZ1(UILabel, setText_, NSString *)
DEF_SWZ1(UINavigationItem, setTitle_, NSString *)
DEF_SWZ1(UIViewController, setTitle_, NSString *)
DEF_SWZ1(UITabBarItem, setTitle_, NSString *)
DEF_SWZ1(UITextField, setPlaceholder_, NSString *)
DEF_SWZ1(UITextView, setText_, NSString *)
DEF_SWZ1(UISearchBar, setPlaceholder_, NSString *)
DEF_SWZ1(UITableViewCell, setText_, NSString *)
DEF_SWZ1(SwiftUI_ListTableViewCell, setText_, NSString *)
DEF_SWZ1(SwiftUI_ListTableViewHeaderFooter, setText_, NSString *)
DEF_SWZ1(SideStore_InsetGroupTableViewCell, setText_, NSString *)
DEF_SWZ1(SideStore_AppContentTableViewCell, setText_, NSString *)
DEF_SWZ1(SideStore_SettingsHeaderFooterView, setText_, NSString *)
DEF_SWZ1(JetUI_DynamicLabel, setText_, NSString *)
static void (*orig_JetUI_DynamicLabel__setText_)(id, SEL, NSString *);
static void hook_JetUI_DynamicLabel__setText_(id self, SEL _cmd, NSString *v) { orig_JetUI_DynamicLabel__setText_(self, _cmd, cn(v) ?: v); }
DEF_SWZ1(UIListContentConfiguration, setText_, NSString *)
DEF_SWZ1(UIListContentConfiguration_, setSecondaryText_, NSString *)
DEF_SWZ1(UIButtonConfiguration, setTitle_, NSString *)
DEF_SWZ1(UIButtonConfiguration_, setSubtitle_, NSString *)

static void (*orig_UIButton_setTitle)(id, SEL, NSString *, NSUInteger);
static void hook_UIButton_setTitle(id self, SEL _cmd, NSString *t, NSUInteger st) {
    orig_UIButton_setTitle(self, _cmd, cn(t) ?: t, st);
}
static void (*orig_UISegmented_setTitle)(id, SEL, NSString *, NSUInteger);
static void hook_UISegmented_setTitle(id self, SEL _cmd, NSString *t, NSUInteger i) {
    orig_UISegmented_setTitle(self, _cmd, cn(t) ?: t, i);
}
static id (*orig_UIAlertAction_action)(id, SEL, NSString *, NSInteger, id);
static id hook_UIAlertAction_action(id self, SEL _cmd, NSString *t, NSInteger style, id handler) {
    return orig_UIAlertAction_action(self, _cmd, cn(t) ?: t, style, handler);
}
static id (*orig_UIAlertController_alert)(id, SEL, NSString *, NSString *, NSInteger);
static id hook_UIAlertController_alert(id self, SEL _cmd, NSString *t, NSString *m, NSInteger style) {
    return orig_UIAlertController_alert(self, _cmd, cn(t) ?: t, cn(m) ?: m, style);
}
// attributed 系列：保留属性包中文
static void (*orig_UILabel_setAttr)(id, SEL, NSAttributedString *);
static void hook_UILabel_setAttr(id self, SEL _cmd, NSAttributedString *a) {
    if (a) { NSString *r = cn([a string]); if (r) { NSDictionary *at = [a length] ? [a attributesAtIndex:0 effectiveRange:NULL] : nil; a = [[NSAttributedString alloc] initWithString:r attributes:at]; } }
    orig_UILabel_setAttr(self, _cmd, a);
}
static void (*orig_UITextField_setAttr)(id, SEL, NSAttributedString *);
static void hook_UITextField_setAttr(id self, SEL _cmd, NSAttributedString *a) {
    if (a) { NSString *r = cn([a string]); if (r) { NSDictionary *at = [a length] ? [a attributesAtIndex:0 effectiveRange:NULL] : nil; a = [[NSAttributedString alloc] initWithString:r attributes:at]; } }
    orig_UITextField_setAttr(self, _cmd, a);
}
static void (*orig_UIButton_setAttrTitle)(id, SEL, NSAttributedString *, NSUInteger);
static void hook_UIButton_setAttrTitle(id self, SEL _cmd, NSAttributedString *a, NSUInteger st) {
    if (a) { NSString *r = cn([a string]); if (r) { NSDictionary *at = [a length] ? [a attributesAtIndex:0 effectiveRange:NULL] : nil; a = [[NSAttributedString alloc] initWithString:r attributes:at]; } }
    orig_UIButton_setAttrTitle(self, _cmd, a, st);
}
static void (*orig_JetUI_DynamicLabel_setAttr)(id, SEL, NSAttributedString *);
static void hook_JetUI_DynamicLabel_setAttr(id self, SEL _cmd, NSAttributedString *a) {
    if (a) { NSString *r = cn([a string]); if (r) { NSDictionary *at = [a length] ? [a attributesAtIndex:0 effectiveRange:NULL] : nil; a = [[NSAttributedString alloc] initWithString:r attributes:at]; } }
    orig_JetUI_DynamicLabel_setAttr(self, _cmd, a);
}
static void (*orig_CATextLayer_setString)(id, SEL, id);
static void hook_CATextLayer_setString(id self, SEL _cmd, id v) {
    if ([v isKindOfClass:[NSAttributedString class]]) {
        NSString *r = cn([(NSAttributedString *)v string]);
        if (r) { NSDictionary *at = [(NSAttributedString *)v length] ? [(NSAttributedString *)v attributesAtIndex:0 effectiveRange:NULL] : nil; v = [[NSAttributedString alloc] initWithString:r attributes:at]; }
    } else if ([v isKindOfClass:[NSString class]]) {
        NSString *r = cn((NSString *)v); if (r) v = r;
    }
    orig_CATextLayer_setString(self, _cmd, v);
}
// NSBundle 本地化
static NSString *(*orig_NSBundle_localized)(id, SEL, NSString *, NSString *, NSString *);
static NSString *hook_NSBundle_localized(id self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    NSString *r = cn(key);
    if (r) return r;
    return orig_NSBundle_localized(self, _cmd, key, value, table);
}

// ===================== CoreText 原生替换（缓存 attr→typesetter，滚动零开销）=====================
static CFHashCode ptrHash(const void *v) { return (CFHashCode)((uintptr_t)v >> 4); }
static Boolean ptrEqual(const void *a, const void *b) { return a == b; }
static CFDictionaryKeyCallBacks PtrKeyCB = { 0, NULL, NULL, NULL, ptrEqual, ptrHash };
static CFMutableDictionaryRef g_tsCache = NULL;

// 命中后顺手把对象内部 ivar 改成中文：该对象此后永久为中文
static void rewriteObjectIvar(NSAttributedString *o, NSString *hit) {
    static Class clsCached = nil, clsMutable = nil;
    if (!clsCached) { clsCached = objc_getClass("_NSCachedAttributedString"); clsMutable = objc_getClass("NSConcreteMutableAttributedString"); }
    Ivar iv = nil;
    if (clsCached && [o isKindOfClass:clsCached]) iv = class_getInstanceVariable(clsCached, "_contents");
    else if (clsMutable && [o isKindOfClass:clsMutable]) iv = class_getInstanceVariable(clsMutable, "mutableString");
    if (iv) object_setIvar(o, iv, (__bridge id)CFBridgingRetain(hit)); // CFBridgingRetain +1，__bridge 仅转类型不再插手，永久持有
}

static CTTypesetterRef (*orig_CTTypesetterCreate)(CFAttributedStringRef);
static CTTypesetterRef hook_CTTypesetterCreate(CFAttributedStringRef attr) {
    if (!attr) return orig_CTTypesetterCreate(attr);
    CTTypesetterRef cached = (CTTypesetterRef)CFDictionaryGetValue(g_tsCache, attr);
    if (cached) { CFRetain(cached); return cached; }
    NSString *s = (__bridge NSString *)CFAttributedStringGetString(attr);
    NSString *hit = cn(s);
    if (!hit) return orig_CTTypesetterCreate(attr);
    NSDictionary *attrs = [(__bridge NSAttributedString *)attr length] ? [(__bridge NSAttributedString *)attr attributesAtIndex:0 effectiveRange:NULL] : nil;
    NSAttributedString *nattr = [[NSAttributedString alloc] initWithString:hit attributes:attrs];
    CTTypesetterRef nt = orig_CTTypesetterCreate((__bridge CFAttributedStringRef)nattr);
    if (CFDictionaryGetCount(g_tsCache) > 800) CFDictionaryRemoveAllValues(g_tsCache);
    CFDictionarySetValue(g_tsCache, attr, nt);   // value +1 由 dict 持有
    rewriteObjectIvar((__bridge NSAttributedString *)attr, hit);
    return nt;
}
static CTLineRef (*orig_CTLineCreate)(CFAttributedStringRef);
static CTLineRef hook_CTLineCreate(CFAttributedStringRef attr) {
    if (!attr) return orig_CTLineCreate(attr);
    CTLineRef cached = (CTLineRef)CFDictionaryGetValue(g_tsCache, attr);
    if (cached) { CFRetain(cached); return cached; }
    NSString *s = (__bridge NSString *)CFAttributedStringGetString(attr);
    NSString *hit = cn(s);
    if (!hit) return orig_CTLineCreate(attr);
    NSDictionary *attrs = [(__bridge NSAttributedString *)attr length] ? [(__bridge NSAttributedString *)attr attributesAtIndex:0 effectiveRange:NULL] : nil;
    NSAttributedString *nattr = [[NSAttributedString alloc] initWithString:hit attributes:attrs];
    CTLineRef nt = orig_CTLineCreate((__bridge CFAttributedStringRef)nattr);
    if (CFDictionaryGetCount(g_tsCache) > 800) CFDictionaryRemoveAllValues(g_tsCache);
    CFDictionarySetValue(g_tsCache, attr, nt);
    rewriteObjectIvar((__bridge NSAttributedString *)attr, hit);
    return nt;
}
static CTFramesetterRef (*orig_CTFramesetterCreate)(CFAttributedStringRef);
static CTFramesetterRef hook_CTFramesetterCreate(CFAttributedStringRef attr) {
    if (!attr) return orig_CTFramesetterCreate(attr);
    CTFramesetterRef cached = (CTFramesetterRef)CFDictionaryGetValue(g_tsCache, attr);
    if (cached) { CFRetain(cached); return cached; }
    NSString *s = (__bridge NSString *)CFAttributedStringGetString(attr);
    NSString *hit = cn(s);
    if (!hit) return orig_CTFramesetterCreate(attr);
    NSDictionary *attrs = [(__bridge NSAttributedString *)attr length] ? [(__bridge NSAttributedString *)attr attributesAtIndex:0 effectiveRange:NULL] : nil;
    NSAttributedString *nattr = [[NSAttributedString alloc] initWithString:hit attributes:attrs];
    CTFramesetterRef nt = orig_CTFramesetterCreate((__bridge CFAttributedStringRef)nattr);
    if (CFDictionaryGetCount(g_tsCache) > 800) CFDictionaryRemoveAllValues(g_tsCache);
    CFDictionarySetValue(g_tsCache, attr, nt);
    rewriteObjectIvar((__bridge NSAttributedString *)attr, hit);
    return nt;
}

// ===================== CFString 创建级兜底（拷贝语义，安全）=====================
static CFStringRef (*orig_CFStringCreateWithCString)(CFAllocatorRef, const char *, CFStringEncoding);
static std::unordered_map<std::string, std::string> &BYTES() {
    static std::unordered_map<std::string, std::string> *m = nullptr;
    if (!m) m = new std::unordered_map<std::string, std::string>();
    return *m;
}
static CFStringRef hook_CFStringCreateWithCString(CFAllocatorRef a, const char *c, CFStringEncoding e) {
    if (c) {
        unsigned char b0 = (unsigned char)c[0];
        if ((b0 >= 'A' && b0 <= 'Z') || (b0 >= 'a' && b0 <= 'z')) {
            std::string k(c);
            if (k.size() >= 2 && k.size() <= 480) {
                auto &t = TABLE();
                auto it = t.find(k);
                if (it == t.end()) {
                    std::string lo(k);
                    for (auto &ch : lo) ch = (char)tolower((unsigned char)ch);
                    it = TABLE_LOWER().find(lo);
                }
                if (it != t.end()) {
                    auto &bm = BYTES();
                    std::string &buf = bm[it->second];
                    if (buf.empty()) buf = it->second;
                    return orig_CFStringCreateWithCString(a, buf.c_str(), e);
                }
            }
        }
    }
    return orig_CFStringCreateWithCString(a, c, e);
}

// ===================== CFBundle 本地化 =====================
static CFStringRef (*orig_CFBundleCopyLocalizedString)(CFBundleRef, CFStringRef, CFStringRef, CFStringRef);
static CFStringRef hook_CFBundleCopyLocalizedString(CFBundleRef b, CFStringRef key, CFStringRef value, CFStringRef table) {
    if (key) {
        NSString *hit = cn((__bridge NSString *)key);
        if (hit) return (CFStringRef)CFBridgingRetain(hit);
    }
    return orig_CFBundleCopyLocalizedString(b, key, value, table);
}

// ===================== 注入入口 =====================
__attribute__((constructor)) static void sidestore_cn_init() {
    @autoreleasepool {
        TABLE(); TABLE_LOWER(); TABLE_FOLD();
        g_tsCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &PtrKeyCB, &kCFTypeDictionaryValueCallBacks);

        swz("UILabel", "setText:", (IMP)hook_UILabel_setText_, (IMP *)&orig_UILabel_setText_);
        swz("UINavigationItem", "setTitle:", (IMP)hook_UINavigationItem_setTitle_, (IMP *)&orig_UINavigationItem_setTitle_);
        swz("UIViewController", "setTitle:", (IMP)hook_UIViewController_setTitle_, (IMP *)&orig_UIViewController_setTitle_);
        swz("UITabBarItem", "setTitle:", (IMP)hook_UITabBarItem_setTitle_, (IMP *)&orig_UITabBarItem_setTitle_);
        swz("UITextField", "setPlaceholder:", (IMP)hook_UITextField_setPlaceholder_, (IMP *)&orig_UITextField_setPlaceholder_);
        swz("UITextView", "setText:", (IMP)hook_UITextView_setText_, (IMP *)&orig_UITextView_setText_);
        swz("UISearchBar", "setPlaceholder:", (IMP)hook_UISearchBar_setPlaceholder_, (IMP *)&orig_UISearchBar_setPlaceholder_);
        swz("UITableViewCell", "setText:", (IMP)hook_UITableViewCell_setText_, (IMP *)&orig_UITableViewCell_setText_);
        swz("SwiftUI.ListTableViewCell", "setText:", (IMP)hook_SwiftUI_ListTableViewCell_setText_, (IMP *)&orig_SwiftUI_ListTableViewCell_setText_);
        swz("SwiftUI.ListTableViewHeaderFooter", "setText:", (IMP)hook_SwiftUI_ListTableViewHeaderFooter_setText_, (IMP *)&orig_SwiftUI_ListTableViewHeaderFooter_setText_);
        swz("SideStore.InsetGroupTableViewCell", "setText:", (IMP)hook_SideStore_InsetGroupTableViewCell_setText_, (IMP *)&orig_SideStore_InsetGroupTableViewCell_setText_);
        swz("SideStore.AppContentTableViewCell", "setText:", (IMP)hook_SideStore_AppContentTableViewCell_setText_, (IMP *)&orig_SideStore_AppContentTableViewCell_setText_);
        swz("SideStore.SettingsHeaderFooterView", "setText:", (IMP)hook_SideStore_SettingsHeaderFooterView_setText_, (IMP *)&orig_SideStore_SettingsHeaderFooterView_setText_);
        swz("JetUI.DynamicLabel", "setText:", (IMP)hook_JetUI_DynamicLabel_setText_, (IMP *)&orig_JetUI_DynamicLabel_setText_);
        swz("JetUI.DynamicLabel", "_setText:", (IMP)hook_JetUI_DynamicLabel__setText_, (IMP *)&orig_JetUI_DynamicLabel__setText_);
        swz("UIListContentConfiguration", "setText:", (IMP)hook_UIListContentConfiguration_setText_, (IMP *)&orig_UIListContentConfiguration_setText_);
        swz("UIListContentConfiguration", "setSecondaryText:", (IMP)hook_UIListContentConfiguration__setSecondaryText_, (IMP *)&orig_UIListContentConfiguration__setSecondaryText_);
        swz("UIButtonConfiguration", "setTitle:", (IMP)hook_UIButtonConfiguration_setTitle_, (IMP *)&orig_UIButtonConfiguration_setTitle_);
        swz("UIButtonConfiguration", "setSubtitle:", (IMP)hook_UIButtonConfiguration__setSubtitle_, (IMP *)&orig_UIButtonConfiguration__setSubtitle_);
        swz("UIButton", "setTitle:forState:", (IMP)hook_UIButton_setTitle, (IMP *)&orig_UIButton_setTitle);
        swz("UISegmentedControl", "setTitle:forSegmentAtIndex:", (IMP)hook_UISegmented_setTitle, (IMP *)&orig_UISegmented_setTitle);
        swzClassMethod("UIAlertAction", "actionWithTitle:style:handler:", (IMP)hook_UIAlertAction_action, (IMP *)&orig_UIAlertAction_action);
        swzClassMethod("UIAlertController", "alertControllerWithTitle:message:preferredStyle:", (IMP)hook_UIAlertController_alert, (IMP *)&orig_UIAlertController_alert);
        swz("UILabel", "setAttributedText:", (IMP)hook_UILabel_setAttr, (IMP *)&orig_UILabel_setAttr);
        swz("UITextField", "setAttributedText:", (IMP)hook_UITextField_setAttr, (IMP *)&orig_UITextField_setAttr);
        swz("UIButton", "setAttributedTitle:forState:", (IMP)hook_UIButton_setAttrTitle, (IMP *)&orig_UIButton_setAttrTitle);
        swz("JetUI.DynamicLabel", "setAttributedText:", (IMP)hook_JetUI_DynamicLabel_setAttr, (IMP *)&orig_JetUI_DynamicLabel_setAttr);
        swz("CATextLayer", "setString:", (IMP)hook_CATextLayer_setString, (IMP *)&orig_CATextLayer_setString);
        swz("NSBundle", "localizedStringForKey:value:table:", (IMP)hook_NSBundle_localized, (IMP *)&orig_NSBundle_localized);

        MSHookFunction((void *)CTTypesetterCreateWithAttributedString, (void *)hook_CTTypesetterCreate, (void **)&orig_CTTypesetterCreate);
        MSHookFunction((void *)CTLineCreateWithAttributedString, (void *)hook_CTLineCreate, (void **)&orig_CTLineCreate);
        MSHookFunction((void *)CTFramesetterCreateWithAttributedString, (void *)hook_CTFramesetterCreate, (void **)&orig_CTFramesetterCreate);
        MSHookFunction((void *)CFStringCreateWithCString, (void *)hook_CFStringCreateWithCString, (void **)&orig_CFStringCreateWithCString);
        MSHookFunction((void *)CFBundleCopyLocalizedString, (void *)hook_CFBundleCopyLocalizedString, (void **)&orig_CFBundleCopyLocalizedString);
    }
}
