# Debug 模拟器演示录制验证

2026-10-29，以已发布 `v1.1.3` 为基础。PR 只包含模拟器录制所需的应用代码与本报告；视频制作工程、AI 素材和最终成片不在 PR 中发布，保留为本地制作文件及独立交付物。

## 环境与输入

macOS 26.6.2，Xcode 27.1（27A9275），iPhone 17 / iOS 27.0 Simulator，scheme `GloWalk`。构建 Debug、Release，构建与过程文件使用任务临时目录，没有修改既有 Bundle ID。

等价复现命令，`SIMULATOR_ID` 使用本机可用的 iPhone 模拟器：

```sh
xcodebuild -project GloWalk.xcodeproj -scheme GloWalk \
  -configuration Debug -destination "id=$SIMULATOR_ID" \
  -derivedDataPath "$TMPDIR/glowalk-promo-build" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$SIMULATOR_ID" \
  "$TMPDIR/glowalk-promo-build/Build/Products/Debug-iphonesimulator/GloWalk.app"
xcrun simctl launch "$SIMULATOR_ID" wang.xingyu.glowalk \
  --promo-walk -AppleLanguages '(zh-Hans)' -language zh-Hans
```

`--promo-walk` 仅在 Debug 模拟器解析。每秒增加两步，以固定的正弦曲线生成步行速度附近的位置，同时变化环境光与手机姿态。位置进入现有 LocationManager 的计步门控、距离与分段流程，海报也使用现有生成器。天气固定为演示值，日期取当天 21:14。演示使用内存数据库，跳过真实传感器、天气请求和 Health 同步。

## 实际结果

| 检查 | 结果 |
| --- | --- |
| Debug 编译、安装、启动 | 通过，最终代码重新安装运行 |
| 计步、距离与轨迹增长 | 通过，观察到连续增长及金色轨迹 |
| 上拖调亮、下拖调暗 | 通过，光晕位置、亮度档位和手动模式提示同步变化 |
| 暂停、继续 | 通过；录制时暂停保持 356 步 / 210 米；最终代码暂停保持 336 步 / 198 米，恢复后为 342 步 / 200 米，没有重复累计 |
| 取消结束 | 通过，关闭确认后记录继续，随后为 846 步 / 489 米 |
| 确认结束、生成海报 | 通过，完成记录为 948 步 / 555 米 / 7 分钟，纪念语反映暂停分段 |
| 保存、历史 | 通过，保存按钮变为“已保存”，导出 JPEG；历史显示本周 1 次、555 米、948 步及对应 21:14 条目 |
| 正常存储隔离 | 演示使用内存存储，随后运行 Release 仍为正常首次使用隐私页，演示行程未进入正常历史 |
| Release 编译与参数隔离 | 通过；传入同一参数仍进入正常隐私页，二进制不含 `--promo-walk` 字面量 |
| 健康、天气隔离 | 代码检查确认跳过启动及重试天气请求、两处 Health 同步入口；不把此项当作真实 Health 写入验收 |

## 范围与留存

按新增演示流程选择直接端到端路径及 Debug / Release 编译，没有新增单元测试，没有运行无关模块的本地全面回归；现有 PR CI 按仓库配置执行，其结果以 GitHub 检查为准。

两种配置均保留基础版本已有的四项 CoreData / Combine 导入警告。没有实体 iPhone、真实传感器、照明闭环、耗电或发热验收；宣传中的 AI 场景不作为性能证据。

只保留本报告。检查截图、完整录制、临时数据库、日志和构建输出不进入 Git，并在任务结束后清除。为宣传片选定的正式输入及成片独立保存在本地，不作为测试附件发布。
