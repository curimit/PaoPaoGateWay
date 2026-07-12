# 在裸机上部署

物理机不需要 NoCloud 数据源,装好 Ubuntu Server 后直接运行安装脚本即可。

## 1. 安装 Ubuntu Server

用官方 ISO 正常安装 Ubuntu Server 24.04 LTS(最小化安装即可),确保:

- 至少一个网口接入 LAN(单臂部署模型;安装完成后任意网口插线均可,全部网口自动 DHCP)
- 安装时配置好网络(DHCP 或静态均可)与一个管理用户

## 2. 运行安装脚本

```bash
# 国内网络走镜像(任选其一,失败换下一个):
curl -fsSL https://ghfast.top/https://github.com/curimit/PaoPaoGateWay/releases/latest/download/install.sh | sudo bash
# 或直连:
curl -fsSL https://github.com/curimit/PaoPaoGateWay/releases/latest/download/install.sh | sudo bash
```

可选环境变量(加在 `sudo` 之后、`bash` 之前,例如 `sudo PPGW_SNIFF=no bash`):

| 变量 | 说明 |
|---|---|
| `PPGW_BASE_URL` | 从局域网 HTTP 源下载 payload,如 `http://192.168.1.2:8080/ppgw` |
| `PPGW_SNIFF` | `yes`(默认)/`no`,是否启用 sing-box 域名嗅探链 |
| `PPGW_SHA256` | 手工固定 payload 的 sha256 |

## 3. 配置并重启

- **配合 PaoPaoDNS**:无需任何本地配置,重启后网关自动从 `http://paopao.dns:7889` 发现配置
- **独立使用**:创建 `/www/ppgw.ini`(参数见 README 配置参考)后重启

```bash
sudo reboot
```

重启后 `ppgw.service` 自动启动,访问 `http://<主机IP>/ui` 打开面板。

> 多网卡机器:所有网口均开启 DHCP,网关自动使用持有默认路由的那个网口,插任意口即可。
