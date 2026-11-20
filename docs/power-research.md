# 电源管理方案

最低系统版本为 macOS 26.0。第一版使用 SwiftUI 菜单栏、IOKit 电源通知和经用户批准的 `SMAppService` 后台组件。目标场景包括只有充电器的合盖使用。

- **合盖触发系统休眠。** 在 Apple 的说明中，合盖与闲置属于两种触发机制。普通闲置休眠断言适合保护开盖的任务。Foldwake 和 Lid Awake 都让一个固定职责的 helper 应用 `SleepDisabled`。 [Apple 休眠说明](https://developer.apple.com/library/archive/qa/qa1340/_index.html) · [Foldwake 实现](https://github.com/thavguard/foldwake/blob/main/docs/ARCHITECTURE.md) · [Lid Awake 电源模型](https://github.com/thuongtin/lid-awake/blob/main/docs/power-model.md)
- **禁睡作用于整机。** Apple 的实现将 `disablesleep` 放进全局电源设置。`-c` 可给 `displaysleep` 选择外接电源配置。只有正使用外接电源时才应用禁睡，即使插着电但电池正在暂停充电也按系统报告的供电来源处理。接管前先写恢复记录，应用和恢复都回读。恢复一项成功后交还它的控制权，失败项保留记录重试。IOKit 提供电源通知，后台组件会补查可能漏掉的电源变化。 [Apple 的 pmset 源码](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m#L5414-L5440) · [Apple 的 pmset 手册](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.1#L60-L93) · [IOKit 电源通知](https://developer.apple.com/documentation/iokit/1523868-iopsnotificationcreaterunloopsou)
- **已有覆盖有独立归属。** 初始 `SleepDisabled=1` 时提示已有禁睡，保留其设置。恢复显示器时对照自己写过的值，保留用户后来在系统设置里修改的时长。多个工具写入同一个全局值时，系统读回无法区分写入者，建议各工具分时使用。
- **用户会话拥有覆盖。** XPC 只接受符合同一 Apple 签名团队和预期标识的进程。应用退出、XPC 断开、控制会话换用户、助手收到正常停止请求，都会尝试恢复。助手启动时先处理已有的恢复记录。 [Apple 后台组件文档](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos) · [Apple 对 XPC 签名校验的说明](https://developer.apple.com/forums/thread/681053)
- **一个空闲计时足够。** 用接电配置的显示器休眠时长和系统的立即要求密码联动。合盖时内屏可能从显示列表移除，需要在真机确认当时的锁屏行为。若需要显式锁屏，优先验证 Apple 快捷指令的「锁定显示器」动作。Amphetamine 的问题报告记录过固定键码在 Dvorak 上失效。 [Apple 锁屏说明](https://support.apple.com/zh-cn/guide/mac-help/mchlp2270/27/mac/27) · [Apple 快捷指令动作](https://support.apple.com/en-us/101583) · [Amphetamine 键位问题记录](https://github.com/x74353/Amphetamine/issues/18)

## 真机验收

这一阶段通过编译、应用包结构检查和模拟测试验收。以下场景留待启用真机验证时检查。

1. 只插充电器，接电合盖后后台任务持续，开盖需要解锁。
2. 开盖达到空闲时长时屏幕熄灭，唤醒需要解锁，后台任务继续。
3. 合盖时直接拔电，读取原电源配置并确认系统进入休眠。若系统未自动重新进入休眠，再评估断电时的显式休眠动作。
4. 关闭开关、退出应用或重启助手后恢复原值。之后从深度睡眠唤醒，检查显示和锁屏。Amphetamine 有一份 Tahoe 26 唤醒黑屏报告，报告者未确认根因。 [Amphetamine 唤醒问题记录](https://github.com/x74353/Amphetamine/issues/16)
