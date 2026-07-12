# 定制 seed ISO

设计原则:**免构建、文件级定制**。你只需要编辑 ISO 里的一个明文配置文件 `ppgw.conf`,然后用盘内自带的脚本重新封盘——不需要克隆仓库,更不需要理解构建链。

## 最常用:改 ppgw.conf 后重打包

在任意 Linux 机器上(需要 `xorriso` 和 `dpkg-deb`,Debian/Ubuntu: `apt install xorriso`;Windows 用户可用 WSL):

```bash
# 1. 解出 ISO 内容
xorriso -osirrox on -indev ppgw-seed.iso -extract / seed/
chmod -R u+w seed/

# 2. 编辑配置(SSH 公钥、密码、静态 IP、ppgw.ini 覆盖项,均有注释)
vi seed/ppgw.conf

# 3. 重新封盘(自动把 ppgw.conf 编译进配置包、刷新 instance-id)
bash seed/tools/make-seed.sh -C seed/ -o my-seed.iso
```

或者一条命令直接重封(`--from-iso` 自动完成解包):

```bash
bash seed/tools/make-seed.sh --from-iso ppgw-seed.iso -o my-seed.iso
# 配合 --ssh-key / --password / --hostname 可不落盘直接覆盖对应项:
bash seed/tools/make-seed.sh --from-iso ppgw-seed.iso \
  --ssh-key "ssh-ed25519 AAAA... you@host" -o my-seed.iso
```

把 `my-seed.iso` 挂到 VM 光驱开机即可。

## ppgw.conf 参数

| 键 | 说明 |
|---|---|
| `ssh_authorized_key` | SSH 公钥(填写后可公钥登录;SSH 永远不开密码登录) |
| `password` | 控制台密码;两者都不填时默认 `paopao` 并强制首登修改 |
| `login_user` | 登录账户,默认 `root`(设备型系统不额外建用户);指定其他用户名时自动创建 |
| `hostname` | 主机名,默认 `PaoPaoGW` |
| `net_mode` / `static_ip` / `static_gateway` / `static_dns` | 默认全口 DHCP;`net_mode="static"` 时写静态地址 |
| `ini_*` | 任意 `ini_` 前缀的键会去掉前缀写入 `/www/ppgw.ini`(如 `ini_mode`、`ini_suburl`);全部留空 = PaoPaoDNS 自动发现 |

## 对已部署的 VM 重新下发配置

编辑 `ppgw.conf` → 重打包 → 用新 ISO 替换 VM 光驱 → 重启。每次重打包都会刷新 cloud-init 的 instance-id 并递增配置包版本,开机会自动重新应用,无需重装系统。

## 替换构件(geo 数据 / 内核 / 面板)

软件按功能拆成独立的 deb,放在 ISO 的 `debs/` 目录,可以整包替换:

| 构件 | 包 |
|---|---|
| geodata(geoip/geosite/ASN) | `ppgw-geodata_*.deb` |
| mihomo 内核 / ppgw / sing-box / 运行时脚本 | `ppgw-core_*.deb` |
| Web 面板 | `ppgw-dashboard_*.deb` |

改包内文件用 `dpkg-deb` 解包重打(记得抬高版本号,否则已装机器不会更新):

```bash
dpkg-deb -R ppgw-geodata_20260712+gabc1234_all.deb pkgtmp/
cp my-geoip.metadb pkgtmp/etc/config/clash/geoip.metadb
sed -i 's/^Version: .*/Version: 20260712+custom1/' pkgtmp/DEBIAN/control
dpkg-deb --root-owner-group -b pkgtmp/ ppgw-geodata_20260712+custom1_all.deb
```

替换 `seed/debs/` 里对应的 deb 后照常 `make-seed.sh` 重封。已部署的机器也可以直接 `apt-get install ./ppgw-geodata_*.deb` 就地升级。

## 关闭 sing-box 嗅探链

默认开启(与原版 ISO 的 `SNIFF=yes` 一致)。关闭:装机后执行

```bash
sudo touch /etc/ppgw/no_sniff
sudo apt-get install --reinstall ./ppgw-core_*.deb   # 或等下次升级生效
sudo reboot
```

## 从源码构建

克隆仓库后 `bash build-bundle.sh`(需要 docker、curl、git、dpkg-deb、xorriso),产出与 Release 相同的 `dist/ppgw-seed.iso` 与 `dist/ppgw-offline.tar.gz`;`make-seed.sh` 也可在仓库内直接使用。
