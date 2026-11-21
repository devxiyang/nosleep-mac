# 电源管理方案

最低系统版本为 macOS 26.0。第一版使用 SwiftUI 菜单栏、IOKit 电源通知和经用户批准的 `SMAppService` 后台组件。目标场景包括只有充电器的合盖使用。

- **合盖触发系统休眠。** 在 Apple 的说明中，合盖与闲置属于两种触发机制。普通闲置休眠断言适合保护开盖的任务。Foldwake 和 Lid Awake 都让一个固定职责的 helper 应用 `SleepDisabled`。 [Apple 休眠说明](https://developer.apple.com/library/archive/qa/qa1340/_index.html) · [Foldwake 实现](https://github.com/thavguard/foldwake/blob/main/docs/ARCHITECTURE.md) · [Lid Awake 电源模型](https://github.com/thuongtin/lid-awake/blob/main/docs/power-model.md)
- **禁睡作用于整机。** Apple 的实现将 `disablesleep` 放进全局电源设置。`-c` 可给 `displaysleep` 选择外接电源配置。只有正使用外接电源时才应用禁睡，即使插着电但电池正在暂停充电也按系统报告的供电来源处理。接管前先写恢复记录，应用和恢复都回读。恢复一项成功后交还它的控制权，失败项保留记录重试。IOKit 提供电源通知，后台组件会补查可能漏掉的电源变化。 [Apple 的 pmset 源码](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m#L5414-L5440) · [Apple 的 pmset 手册](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.1#L60-L93) · [IOKit 电源通知](https://developer.apple.com/documentation/iokit/1523868-iopsnotificationcreaterunloopsou)
- **已有覆盖有独立归属。** 初始 `SleepDisabled=1` 时提示已有禁睡，保留其设置。恢复显示器时对照自己写过的值，保留用户后来在系统设置里修改的时长。多个工具写入同一个全局值时，系统读回无法区分写入者，建议各工具分时使用。
- **用户会话拥有覆盖。** XPC 只接受符合同一 Apple 签名团队和预期标识的进程。应用退出、XPC 断开、控制会话换用户、助手收到正常停止请求，都会尝试恢复。助手启动时先处理已有的恢复记录。 [Apple 后台组件文档](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos) · [Apple 对 XPC 签名校验的说明](https://developer.apple.com/forums/thread/681053)
- **熄屏和屏保共用一个选定时长。** 接电熄屏仍由系统电源配置触发。用户会话中的屏保组件通过 System Events 的 `delay interval` 读取屏保时长，将早于选定时长的屏保推迟到同一时长。修改前写入当前用户的恢复记录，回读确认后才报告同步。熄屏时由系统要求密码。 [Apple 锁屏说明](https://support.apple.com/zh-cn/guide/mac-help/mchlp2270/27/mac/27) · [Apple Events 权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- **恢复完成后取得新的屏保原值。** 屏保组件在断电、应用连接断开、会话切换或收到结束信号时尝试恢复。组件启动和应用唤醒时先处理之前留下的记录。若当前值来自用户之后的修改，恢复时保留该值。

## 真机验收

这一阶段通过编译、应用包结构检查和模拟测试验收。以下场景留待启用真机验证时检查。

1. 只插充电器，接电合盖后后台任务持续，开盖需要解锁。
2. 允许「系统事件」自动化后，确认屏保时长回读与系统实际采用的时长一致。将系统屏保设成短于 NoSleep 的时长，观察屏幕在选定时长后熄灭，唤醒需要解锁，后台任务继续。
3. 合盖时直接拔电，检查两项原始时长恢复及系统休眠。分别在系统仍运行、已经休眠和恢复尚未完成时重新接电，核对接电配置在系统可执行后重新应用。
4. 关闭保活、退出应用或重启组件后，检查原值恢复。拒绝自动化时，检查合盖保活状态及屏保设置入口。
