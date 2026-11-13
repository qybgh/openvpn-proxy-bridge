# OpenVPN Proxy Bridge

> macOS 出海代理 + 公司 OpenVPN 分流工具

## 适用场景

本工具用于解决 macOS 上出海代理与公司 OpenVPN 同时运行时的网络冲突：

- 公司内网流量走 OpenVPN。
- 网页和其他代理流量继续走出海客户端。
- OpenVPN 到公司服务器的外层连接通过本机 SOCKS5 代理转发。
- 出海客户端改变本地代理端口后，后台服务自动跟随。

工具不依赖特定出海客户端。目前已在 SakuraCat 1.4.5 的普通系统代理模式下验证主要流程。

## 运行环境与依赖

### 必要基础

| 依赖 | 要求 | 说明 |
|---|---|---|
| macOS | Homebrew 当前支持的版本 | 需要 `launchd`、系统代理和管理员权限 |
| Homebrew | 已安装 | 安装器通过 Homebrew 安装或使用 OpenVPN |
| Python | Python 3.8+ | 用于 profile 转换、VPN 多端点解析和代理 UDP 会话清理 |
| 出海客户端 | 本机 SOCKS5，支持 UDP | 可写入 macOS 系统代理，或允许手动填写地址和端口 |
| 公司 VPN | 标准 `.ovpn`、账号和密码 | profile 应只下发公司路由，不使用 `redirect-gateway` 接管默认路由 |
| 权限 | macOS 管理员权限 | 安装 LaunchDaemon、创建 `utun` 和写入 root 专用配置 |

Homebrew 通常已经依赖 Xcode Command Line Tools，并由其提供 `/usr/bin/python3`。如果安装器提示没有 Python 3.8+，执行：

```bash
brew install python
```

安装器会记录实际使用的 Python 路径，后台服务不会依赖终端的临时 `PATH`。

### macOS 内置组件

以下命令由 macOS 提供，无需单独安装：

- `/bin/bash` 和标准 Unix 命令。
- `launchctl`、`plutil`、`scutil`、`osascript`、`sudo`。
- `nc`、`pgrep`、`stat` 等系统工具。

### 工具自动管理

- Homebrew OpenVPN：不存在时自动安装。
- OpenVPN 及其依赖：记录安装归属，卸载时只清理由本工具托管且未被其他 formula 使用的内容。
- Python：只检测和记录，不自动卸载；如果由用户通过 Homebrew 安装，仍由用户自行管理。

### 可选能力

- Clash 兼容的本地控制接口：用于主动删除 OpenVPN 目标 UDP 会话。没有控制接口时，核心连接仍可使用，停止流程依靠 OpenVPN 退出通知和基础等待窗口。
- OpenVPN Connect：仅用于停止本工具后的临时替代连接，不是本工具依赖。

当前实测环境：macOS 15.7.9（Apple Silicon）、SakuraCat 1.4.5、Homebrew OpenVPN 2.7.9、Python 3.9.6。

## 快速开始

请从 GitHub Releases 下载 `openvpn-proxy-bridge-<版本>.tar.gz` 并解压。源码仓库不提交生成的 `.command` 文件；普通用户应使用 Release 工具包。

### 1. 修复执行权限

工具包经聊天软件、网盘或压缩工具传输后，`.command` 文件可能失去执行权限。如果双击无响应或提示 `Permission denied`，在工具包目录执行：

```bash
chmod u+x ./*.command
```

如果 macOS 提示无法验证开发者，在 Finder 中右键脚本，选择“打开”并确认。

### 2. 安装

1. 启动并连接出海代理客户端。
2. 双击 `setup-company-vpn.command`。
3. 选择公司提供的任意 `.ovpn` 文件。
4. 按提示输入管理员密码和公司 VPN 凭据。

安装器会自动安装 Homebrew OpenVPN。若检测到已有 OpenVPN，会询问是否由本工具托管卸载：

- 其他工具也在使用 OpenVPN：选择 `N`。
- 希望本工具负责安装和卸载：选择 `Y`。

安装脚本只完成配置，**不会自动连接公司 VPN**。

安装前请确认：

- 公司 VPN 服务器 IP 没有被出海客户端设置为直连或拦截。
- 公司业务域名已按需要设置为直连。
- `python3 --version` 返回 3.8 或更高版本。

### 3. 连接

双击 `start-company-vpn.command`。若手机收到钉钉或其他二次认证，请及时确认。

只有日志出现以下内容后，脚本才会报告连接成功：

```text
Initialization Sequence Completed
```

## 日常操作

| 脚本 | 用途 |
|---|---|
| `setup-company-vpn.command` | 首次安装 |
| `start-company-vpn.command` | 启动公司 VPN |
| `stop-company-vpn.command` | 停止公司 VPN |
| `status-company-vpn.command` | 查看连接、代理和日志 |
| `update-credentials.command` | 更新公司 VPN 账号或密码 |
| `configure-proxy.command` | 设置手动代理或恢复自动发现 |
| `uninstall-company-vpn.command` | 完整卸载 |

所有脚本均可在 Finder 中双击运行。

从源码参与开发时，统一入口为：

```bash
bin/openvpn-proxy-bridge <子命令>
```

### 启动与停止

启动脚本具有幂等保护：

- 已连接：直接返回，不重启隧道。
- 正在连接：等待当前连接，不启动第二个进程。
- 旧连接异常：先清理，再重新连接。
- 没有 TLS 回包：清理并延迟重试一次。
- `AUTH_FAILED`：停止连接，不连续重试。

停止脚本会清理后台服务、OpenVPN 子进程、公司路由、运行配置和代理 UDP 会话，并等待基础 8 秒释放窗口。停止状态在重启 Mac 后继续保持，直到再次运行启动脚本。

### 更新账号或密码

双击 `update-credentials.command`，输入新凭据。脚本会原子替换凭据并重新连接，无需卸载或重新选择 `.ovpn`。

密码输入错误时不要反复启动，以免触发认证风控。

### 手动设置 SOCKS5

默认从 macOS 系统代理自动读取 SOCKS5 地址和端口。如果出海客户端没有写入系统代理：

1. 双击 `configure-proxy.command`。
2. 输入 `manual`。
3. 输入本机地址和 SOCKS5 端口。
4. 运行启动脚本。

恢复自动发现时，再次运行配置脚本并选择 `auto`。

### 临时使用 OpenVPN Connect

先运行 `stop-company-vpn.command`，确认后台 VPN 已停止，再连接 OpenVPN Connect。

不要同时运行本工具和 OpenVPN Connect 的同一个公司 profile，否则可能产生路由和 DNS 冲突。

## 故障处理

### 未发现 SOCKS5 代理

依次确认：

1. 出海客户端已经连接。
2. 客户端提供 SOCKS5，而不只是 HTTP 代理。
3. SOCKS5 支持 UDP 转发。
4. SOCKS5 端口正在监听。

无法自动发现时，使用 `configure-proxy.command` 手动配置。

### 提示未找到 Python 3.8+

运行：

```bash
brew install python
```

然后重新执行安装脚本。Python 是运行时依赖，不能只在安装完成后删除。

### 公司 VPN 未连接

运行 `status-company-vpn.command`，重点查看：

| 日志 | 含义 |
|---|---|
| `AUTH_FAILED` | 账号、密码或二次认证失败 |
| `TLS Error` | 代理、网络或 VPN 服务器不可达 |
| `Peer Connection Initiated` | 已建立 TLS 通道 |
| `Initialization Sequence Completed` | 隧道连接成功 |

当 VPN 域名解析到多个地址时，OpenVPN 会以 5 秒为单端点轮询超时尝试备用地址。外层等待预算会按实际端点数量计算，并受 130 秒总连接超时限制；全部端点都没有 TLS 回包时，脚本会清理、重新解析地址并重试一次。仍然失败时，先检查出海代理，再运行状态脚本查看日志。

如果所有 VPN 端点都没有 TLS 回包，但本机 SOCKS5 端口仍在监听，通常表示当前出海节点的 UDP 转发不可用。切换出海节点或完全重启出海客户端后，再运行启动脚本。

同时检查出海客户端的自定义路由规则。公司 VPN 服务器 IP 必须按默认规则走代理；设置为直连会绕过出海节点，导致本地网络无法访问 VPN UDP 端口。默认规则已经走代理时无需额外创建 VPN 服务器代理规则。

### SSH 正常但内网页面打不开

SSH 通常不使用 macOS 系统代理，会直接按系统路由进入 OpenVPN，因此可能正常；浏览器会进入出海客户端的系统代理，如果公司业务域名没有直连规则，请求会被发往出海节点并绕过本机 OpenVPN。

在出海客户端中使用以下分流：

| 目标 | 动作 |
|---|---|
| 公司 VPN 服务器 IP | 默认代理；不要设置为直连或拦截 |
| 公司内网业务域名及域名后缀 | 直连 |
| 普通出海网站 | 按出海客户端原有规则 |

这里的“公司业务域名直连”表示由出海客户端交回本机网络栈，目标 IP 随后仍会按 OpenVPN 下发的精确路由进入 `utun`，并不是绕过公司 VPN。

v1.1.0 会在本机把 VPN 服务器域名解析为显式 IP，再交给 SOCKS5，因此广泛的公司业务域名后缀直连规则不会命中 VPN 外层连接。只有在出海客户端的默认规则不走代理时，才需要额外添加 VPN 服务器 IP 的代理规则。

### 公司域名无法访问

先区分路由与 DNS：

```bash
route -n get COMPANY_IP
nc -vz COMPANY_HOST 22
```

公司目标应走 OpenVPN 创建的 `utun`。IP 可达但域名失败时，检查公司 DNS。

### 出海代理发生变化

后台服务每 5 秒检查一次 SOCKS5：

- 端口改变：使用新端口重建 OpenVPN。
- 代理暂时消失：停止 OpenVPN 并等待代理恢复。
- 代理恢复：自动重新连接，可能再次触发二次认证。
- 代理不可用：不会回退为直连公司服务器。

### 增强模式或 TUN 模式

当前仅支持本机 SOCKS5/普通系统代理模式。增强模式或 TUN 模式可能接管公司 DNS 和网段，导致公司内网不可访问。

出现问题时：

1. 完全退出出海客户端。
2. 重新打开客户端，只启用普通系统代理。
3. 等待 VPN 自动恢复；未恢复时运行启动脚本。

若第三方客户端支持 TUN 路由和 Fake IP 排除，可自行排除全部公司网段与公司域名；此配置不属于本工具的通用支持范围。

## 兼容范围

可兼容的出海客户端需要：

- 提供本机 SOCKS5 地址和端口。
- 支持通过 SOCKS5 转发 UDP。
- 写入 macOS 系统代理，或允许手动查询端口。

以下场景不直接支持：

- 只有 HTTP/HTTPS 代理。
- 只有 TUN，不提供本机 SOCKS5。
- SOCKS5 不支持 UDP。
- 增强模式接管公司 DNS 或公司网段。
- 公司 profile 使用 `redirect-gateway` 接管默认路由。

## 工作原理

```text
公司内网流量
  -> OpenVPN utun
  -> 公司网络

OpenVPN 外层连接
  -> 本机 SOCKS5
  -> 出海代理节点
  -> 公司 VPN 服务器

普通代理流量
  -> 出海客户端
```

安装器从原 `.ovpn` 生成受保护的基础配置；每次启动再加入当前 SOCKS5 地址，生成运行配置。公司 VPN 只安装服务端下发的精确路由，因此不会主动接管普通公网流量。

后台服务监控代理端口变化和 OpenVPN 状态。认证失败时停止重试；代理变化时重建隧道；停止时清理本机进程、路由和代理会话。

## 安全与卸载

- 配置、凭据和日志保存在 `/Library/Application Support/Proxy-OpenVPN`。
- 配置目录权限为 `700`，敏感文件权限为 `600`，仅 root 可读。
- OpenVPN 使用 `auth-nocache`，密码不会出现在进程参数中。
- 原始 `.ovpn` 文件不会被修改。
- 不读取或复用 OpenVPN Connect 保存的凭据。

双击 `uninstall-company-vpn.command` 会先执行完整停止，再删除后台服务、配置、凭据和日志。

Homebrew OpenVPN 的处理遵循安装时记录的归属：

- 本工具安装或明确托管的 OpenVPN 会被卸载。
- 安装前已有且未托管的 OpenVPN 会被保留。
- 被其他 formula 使用的共享依赖会被保留。

卸载不会删除 Homebrew、OpenVPN Connect 或用户原始 `.ovpn` 文件。

从 v1.0.0 升级到 v1.1.0 时不支持原地覆盖。请先使用 v1.0.0 的卸载脚本完成卸载，再安装 v1.1.0。详见仓库中的 [升级说明](https://github.com/qybgh/openvpn-proxy-bridge/blob/main/docs/upgrading.md)。
