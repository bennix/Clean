# Clean 发布与本地化

界面翻译位于 `CleanMac/Translations.json`，以简体中文模板为键，包含 en、ja、de、fr、es。动态参数使用 `{0}`、`{1}`，不要更改或遗漏。`L` 仅替换模板参数，不再次解析文件名中的大括号。系统生成的错误信息和文件名按原样显示。原生权限提示使用各 `.lproj/InfoPlist.strings`。

侧栏语言设置保存到当前应用的用户偏好，默认跟随系统。不支持的系统语言回退到英语。切换语言时重扫已显示结果以更新分类标签；系统对话框需重新打开应用后应用所选语言。

## 签名更新

Sparkle 包固定在 2.10.0。Feed：`https://bennix.github.io/Clean/appcast.xml`。默认关闭自动检查，用户可手动启用。不启用系统信息分析。只有通过 `SUPublicEDKey` 验证的更新包才可安装。

私有更新签名密钥保存在发布机器的 macOS 钥匙串，账号为 `Clean-Sparkle`。不得导出到源码、提交到 Git 或放入发行包。Apple 公证凭据同样不得提交。

1. 增加 `MARKETING_VERSION` 和单调递增的 `CURRENT_PROJECT_VERSION`，更新 UI 页脚。
2. 运行单元测试，检查翻译完整性与占位符；Release 使用 Developer ID、Hardened Runtime 和安全时间戳，禁止注入调试权限。构建后执行 `scripts/sign-release.sh /path/to/Clean.app`，按辅助程序 → Sparkle 框架 → 主应用顺序签名；仅签主应用不足以让 SPM 内预编译的辅助程序通过公证。
3. 公证应用并 staple，制作 DMG 时附带 `ThirdPartyNotices/Sparkle-LICENSE.txt`，再签名 DMG，公证 DMG 并 staple，使用 Gatekeeper 验证。挂载 DMG 后验证内部应用。
4. 使用 Sparkle 官方 `sign_update --account Clean-Sparkle` 对最终已 staple 的 DMG 签名。生成签名后不要再修改 DMG。
5. 更新 appcast 的构建号、版本、最小系统、下载地址、文件长度、EdDSA 签名，校验签名和 XML。
6. 提交源码，发布带 DMG、SHA-256 和公证记录的 GitHub Release。确认资产可下载后再发布 appcast，避免客户端看见缺失的安装包。
7. 验证线上 appcast、Release 哈希和应用内“检查更新”，更新门户。保留 `release/Clean-latest.dmg` 及带版本的本地 DMG。

1.1.2 及更早版本没有更新器，需要手动安装 1.2.0；1.2.0 起才支持获取未来版本。
