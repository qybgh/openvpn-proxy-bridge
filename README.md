# OpenVPN Proxy Bridge

> macOS 出海代理 + 公司 OpenVPN 分流工具

## 适用场景

本工具用于解决 macOS 上出海代理与公司 OpenVPN 同时运行时的网络冲突：

- 公司内网流量走 OpenVPN。
- 网页和其他代理流量继续走出海客户端。
- OpenVPN 到公司服务器的外层连接通过本机 SOCKS5 代理转发。
- 出海客户端改变本地代理端口后，后台服务自动跟随。

使用条件：

- 公司提供标准 `.ovpn` 文件。
- 公司 VPN 只下发公司网段或主机路由，不强制接管默认路由。
- 出海客户端提供支持 UDP 的本机 SOCKS5 代理。
- Mac 已安装 Homebrew，当前用户具有管理员权限。

工具不依赖特定出海客户端。目前已在 SakuraCat 1.4.5 的普通系统代理模式下验证主要流程。

## 快速开始

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

### 启动与停止

启动脚本具有幂等保护：

- 已连接：直接返回，不重启隧道。
- 正在连接：等待当前连接，不启动第二个进程。
- 旧连接异常：先清理，再重新连接。
- 没有 TLS 回包：清理并延迟重试一次。
- `AUTH_FAILED`：停止连接，不连续重试。

停止脚本会清理后台服务、OpenVPN 子进程、公司路由、运行配置和代理 UDP 会话。停止状态在重启 Mac 后继续保持，直到再次运行启动脚本。

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

### 公司 VPN 未连接

运行 `status-company-vpn.command`，重点查看：

| 日志 | 含义 |
|---|---|
| `AUTH_FAILED` | 账号、密码或二次认证失败 |
| `TLS Error` | 代理、网络或 VPN 服务器不可达 |
| `Peer Connection Initiated` | 已建立 TLS 通道 |
| `Initialization Sequence Completed` | 隧道连接成功 |

脚本在没有 TLS 回包时会自动清理、等待旧会话释放并重试一次。仍然失败时，先检查出海代理，再运行状态脚本查看日志。

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
