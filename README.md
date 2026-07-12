# PaoPaoGateWay(cloud-init 版)

本项目**就是 [kkkgo/PaoPaoGateWay](https://github.com/kkkgo/PaoPaoGateWay)**——一个基于 FakeIP 的旁路透明网关。与原版没有任何功能区别,仅把运行底座从定制 OpenWrt ISO 适配为标准 Ubuntu + cloud-init:运行时脚本、`ppgw` 程序、Web 面板、配置格式、与 [PaoPaoDNS](https://github.com/kkkgo/PaoPaoDNS) 的配合方式全部同源,**原版文档完全适用**。

- 功能介绍、设计理念请阅读原作者的 [README](https://github.com/kkkgo/PaoPaoGateWay#readme) 与相关博文
- 原版 ISO 形态的完整代码与构建链保留在 [`ppgw/`](ppgw/) 目录,可继续独立构建使用

## 产物与用法

每个 [Release](../../releases/latest) 包含两个产物,部署机全程无需访问外网:

| 产物 | 场景 | 一句话用法 |
|---|---|---|
| `ppgw-seed.iso` | PVE / ESXi / KVM 等虚拟化 | Ubuntu cloud image 做系统盘,本 ISO 挂光驱,开机即用 |
| `ppgw-offline.tar.gz` | 裸机 / 已有 Ubuntu | scp 传入,`sudo ./install.sh`,重启 |

- 虚拟机部署步骤:[docs/deploy-vm.md](docs/deploy-vm.md)
- 裸机部署步骤:[docs/baremetal.md](docs/baremetal.md)
- 定制(SSH 公钥、静态 IP、本地 ppgw.ini、替换 geo/内核):编辑 ISO 内唯一的配置文件 `ppgw.conf` 后一条命令重封,见 [docs/customize.md](docs/customize.md)
- 架构、ppgw.ini 参数、系统改动、FAQ:[docs/reference.md](docs/reference.md)

## 本仓库做的适配

一句话列举:systemd 单元替代 rc.local/procd、netplan 全网口 DHCP、chrony 对时、journald 日志、软件按功能封为 deb 包(core / geodata / dashboard / system / config)、cloud-init NoCloud seed ISO 一次性完成注入与离线安装。运行时逻辑未做任何功能性修改。

## License 与致谢

本项目为 [kkkgo/PaoPaoGateWay](https://github.com/kkkgo/PaoPaoGateWay) 的衍生作品,遵循 [GPL-3.0](LICENSE) 许可发布。**全部核心功能与设计归功于原作者 [@kkkgo](https://github.com/kkkgo)**,同时感谢:

- [mihomo](https://github.com/MetaCubeX/mihomo)(MetaCubeX)— 默认代理内核
- [sing-box](https://github.com/SagerNet/sing-box) 及 [kkkgo/box](https://github.com/kkkgo/box) — 域名嗅探链
- [meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) — geodata 数据
- [PaoPaoDNS](https://github.com/kkkgo/PaoPaoDNS) — 推荐搭配的分流 DNS
