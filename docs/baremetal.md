# 裸机 / 已有 Ubuntu 部署(离线安装包)

物理机或已经装好的 Ubuntu 服务器,使用 `ppgw-offline.tar.gz`:内含全部 deb(ppgw 软件包 + 依赖闭包),**安装全程不需要访问外网**,scp 传进去即可。

安装器**不会改动**你已有的登录方式和网络配置(个性化的 ppgw-config 包只存在于 seed ISO 中)。

## 1. 安装 Ubuntu Server

用官方 ISO 正常安装 Ubuntu Server 24.04 LTS(最小化安装即可),确保:

- 至少一个网口接入 LAN(单臂部署;装完后所有网口自动 DHCP,插任意口均可)
- 配置好一个管理用户

> 离线包按 24.04 cloud image 校准依赖;22.04 大概率可用但未验证,缺包时可 `apt-get -f install` 在线补齐。

## 2. 传输并安装

```bash
# 在有网的机器上下载,再 scp 到目标机
scp ppgw-offline.tar.gz user@gateway:/tmp/

# 在目标机上
cd /tmp && tar -xzf ppgw-offline.tar.gz
sudo ppgw-offline/install.sh
```

可选:安装前 `sudo touch /etc/ppgw/no_sniff` 可关闭 sing-box 域名嗅探链(默认开启,与原版 ISO 一致)。

## 3. 配置并重启

- **配合 PaoPaoDNS**:无需任何本地配置,重启后网关自动从 `http://paopao.dns:7889` 发现配置
- **独立使用**:创建 `/www/ppgw.ini`(参数见 [reference.md](reference.md))后重启

```bash
sudo reboot
```

重启后 `ppgw.service` 自动启动,访问 `http://<主机IP>/ui` 打开面板。

> 注意:安装的 `ppgw-system` 包会接管网络(全部网口 DHCP、关闭 systemd-resolved 的 53 端口监听)。如果这台机器还跑其他服务,请先阅读 [reference.md](reference.md) 了解系统改动项。

## 升级

解开新版 `ppgw-offline.tar.gz` 重新运行 `install.sh` 即可,`/www/` 下的本地配置不受影响。
