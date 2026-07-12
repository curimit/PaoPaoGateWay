# 虚拟机部署(Proxmox VE / ESXi / KVM 等)

所有虚拟化平台使用同一套流程:**Ubuntu cloud image 做系统盘 + `ppgw-seed.iso` 做光驱**。seed ISO 既是 cloud-init 数据源,也内置了全部软件包,**开机安装全程不需要访问外网**。

## 0. 准备文件

1. 从 [Release](../../../releases/latest) 下载 `ppgw-seed.iso`
   - 直接使用:默认 DHCP + PaoPaoDNS 自动发现,控制台用户 `ubuntu`、初始密码 `paopao`(首次登录强制修改),无 SSH
   - 需要 SSH 公钥、静态 IP 或本地 `ppgw.ini`:先按 [customize.md](customize.md) 编辑 `ppgw.conf` 并重打包
2. 下载 Ubuntu 24.04 cloud image:

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

## Proxmox VE

```bash
# 创建 VM(VMID 以 9100 为例,按需调整内存/网桥)
qm create 9100 --name paopao-gateway --memory 1024 --cores 2 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --ostype l26

# 导入系统盘并扩容
qm set 9100 --scsi0 local-lvm:0,import-from=$(pwd)/noble-server-cloudimg-amd64.img
qm disk resize 9100 scsi0 +4G

# 把 seed ISO 上传到存储(或放到 /var/lib/vz/template/iso/),挂为光驱
qm set 9100 --ide2 local:iso/ppgw-seed.iso,media=cdrom --boot order=scsi0 --serial0 socket

qm start 9100
```

> 不要再添加 PVE 自带的 cloud-init 盘(`--ide2 local-lvm:cloudinit`)或 `cicustom`:seed ISO 本身就是 NoCloud 数据源,两个数据源会互相冲突。

## ESXi

1. 部署 Ubuntu cloud image:下载 [OVA 版本](https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.ova),通过 "部署 OVF/OVA 模板" 导入(cloud-init 相关的 OVF 属性全部留空)
2. 将 `ppgw-seed.iso` 上传到数据存储,作为 CD/DVD 挂载,勾选 **打开电源时连接**
3. 建议配置:2 vCPU / 1 GB 内存 / 磁盘扩容至 8 GB+ / 网卡接入 LAN 端口组,开机

## KVM / libvirt

```bash
qemu-img create -f qcow2 -b noble-server-cloudimg-amd64.img -F qcow2 ppgw-disk.qcow2 8G
virt-install --name paopao-gateway --memory 1024 --vcpus 2 \
  --disk ppgw-disk.qcow2,bus=virtio --cdrom ppgw-seed.iso \
  --network bridge=br0,model=virtio --import --osinfo ubuntu24.04 --noautoconsole
```

VirtualBox / Hyper-V 等平台同理:系统盘用 cloud image,光驱挂 `ppgw-seed.iso` 即可。

## 首次启动

首次开机 cloud-init 从光盘离线安装全部软件包,然后自动重启一次。重启完成后:

- 控制台可看到 PaoPaoGW 横幅与运行日志
- 浏览器访问 `http://<VM_IP>/ui` 打开管理面板
- 把需要代理的设备网关/静态路由指向本机 IP

seed ISO 建议保持挂载:之后想改配置,只需按 [customize.md](customize.md) 重打包并替换这张光盘,重启即自动重新应用(无需重装系统)。
