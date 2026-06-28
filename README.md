# Realm 一键安装与配置脚本

这是一个专为 Bandwagon Host (BWG) 及其他 Linux VPS 设计的 Realm 一键管理脚本。它可以帮助你快速搭建端口转发中转服务。

视频教程：https://youtu.be/gtUFnTTsiHQ

## ✨ 功能特点

- 🚀 **自动安装**: 自动检测 CPU 架构并下载最新版 Realm。
- ⚙️ **交互配置**: 无需手写配置文件，通过菜单输入 IP 和端口即可。
- 🔥 **防火墙管理**: 添加规则时自动放行 UFW 端口。
- 🔄 **服务管理**: 自动配置 Systemd 开机自启。
- ⚡️ **快捷管理**: 安装后输入 `realm` 即可随时管理。

## 🛠 使用方法

### 1. 快速安装

登录你的 VPS，运行以下命令即可：

```
bash <(curl -Ls https://raw.githubusercontent.com/playfulsoul/realm-installer/main/install.sh)
```

### 2. 快捷菜单

安装完成后，以后只需在终端输入以下命令即可唤出管理菜单：

```
realm
```

### 3. 菜单功能说明

1. **安装 Realm**: 首次运行请选择此项。
2. **添加转发规则**: 输入监听端口、落地 IP 和落地端口。
3. **查看运行状态**: 检查服务是否正常，并显示当前的转发配置。
4. **更新本脚本**: 如果 GitHub 仓库有更新，点击此项自动同步。
5. **卸载 Realm**: 清理所有文件。

## 📝 常见问题

**Q: 为什么转发不通？**
A: 请检查落地机的防火墙是否允许了中转机的 IP 连接。

**Q: 支持 UDP 吗？**
A: 支持。脚本默认开启 TCP + UDP 双协议转发，完美支持 Hysteria2 和游戏加速。

**Q: 怎么修改已有的规则？**
A: 目前脚本仅支持追加规则。如需修改，请手动编辑 `/etc/realm/config.toml` 然后运行 `systemctl restart realm`。
