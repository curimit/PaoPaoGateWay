# 在 ESXi / 通用虚拟化平台上部署(NoCloud seed ISO)

ESXi 没有原生 cloud-init 数据源,使用 NoCloud 方式:把 user-data 打成一张小 ISO,随 Ubuntu cloud image 一起挂载。同样适用于 KVM、VirtualBox、Hyper-V 等平台。

## 1. 制作 seed ISO

在任意 Linux 机器上:

```bash
# 获取并修改 user-data
wget https://github.com/curimit/PaoPaoGateWay/releases/latest/download/user-data.yaml -O user-data
vi user-data

# meta-data 只需实例标识
cat > meta-data <<'EOF'
instance-id: ppgw-001
local-hostname: PaoPaoGW
EOF

# 二选一:
# a) cloud-image-utils
cloud-localds seed.iso user-data meta-data
# b) genisoimage
genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
```

## 2. 准备系统盘

```bash
# 下载 Ubuntu 24.04 cloud image(OVA 或 img 均可)
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.ova
```

ESXi 上通过 "部署 OVF/OVA 模板" 导入;其他平台把 `.img` 转成对应磁盘格式即可,如 KVM 直接使用 qcow2:

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
qemu-img convert -O vmdk noble-server-cloudimg-amd64.img ppgw-disk.vmdk   # ESXi
```

## 3. 挂载并启动

1. 将 `seed.iso` 上传到数据存储,作为 CD/DVD 挂载到该虚拟机,勾选"打开电源时连接"
2. 建议配置:2 vCPU / 1 GB 内存 / 磁盘扩容至 8 GB+ / 网卡接入 LAN 端口组
3. 开机。首次启动自动安装并重启一次,之后访问 `http://<VM_IP>/ui`

> seed ISO 只在首次启动时被读取,之后可以卸载。
