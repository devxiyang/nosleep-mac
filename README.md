# NoSleep

一个面向 macOS 26 或更新版本的菜单栏工具。打开开关并接通外部电源后，Mac 可以合盖继续运行任务。空闲熄屏和锁屏共用一个时长，可选常用预设或自定义分钟、小时。使用电池、关闭开关或退出时，后台组件恢复它接管的电源设置。

将 NoSleep 拖到「应用程序」后打开，默认在登录 macOS 时启动。可在菜单栏的齿轮设置中关闭，或前往 macOS 的「登录项」管理。菜单语言默认跟随 macOS，可在齿轮设置中切换简体中文、繁體中文、英语、日语、韩语、德语和西班牙语。

NoSleep 使用 macOS 的即时锁屏机制。请在系统设置的「锁屏」中选择显示器关闭后立即要求密码。接电保活期间，NoSleep 会把过早的自动屏保推迟到选定的空闲时长，拔电或退出时恢复原时长。重新接电或唤醒后会按当前供电状态同步。

## 开发

用 Xcode 打开 NoSleep.xcodeproj，选择 NoSleep scheme。也可以运行项目的 Codex Run 操作，或用脚本仅编译应用和后台组件。

`./script/build_and_run.sh --build-only`

配置 Apple 签名团队后，可构建用于将来验证授权的应用。应用和后台组件使用同一签名团队。

`NOSLEEP_DEVELOPMENT_TEAM=YOUR_TEAM_ID ./script/build_and_run.sh --build-only`

无团队时可以编译界面和运行模拟测试。应用会在启用特权组件前提示签名要求。首次启用时，按 macOS 提示批准后台组件，并允许屏保组件控制「系统事件」。如果屏保无法同步，NoSleep 会在空闲时长下方提示并提供系统设置入口。

## 测试

Xcode 的 NoSleep scheme 包含无宿主应用的单元测试。测试使用内存中的电源、屏保和恢复记录，覆盖拔电、快速重连、进程断开、权限失败和外部设置修改。

`xcodebuild -project NoSleep.xcodeproj -scheme NoSleep -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`

[方案依据与真机验收项](docs/power-research.md)
