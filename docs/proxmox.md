# 在 Proxmox VE 上部署

以 Ubuntu 24.04 cloud image 为底,通过 PVE 的 cloud-init `cicustom` 注入 user-data。

## 1. 准备 user-data

下载本仓库的 [`user-data.yaml`](../user-data.yaml),按注释修改(登录方式、`/www/ppgw.ini` 或删除该段走 PaoPaoDNS 自动发现),放到 PVE 的 snippets 存储:

```bash
# 在 PVE 节点上执行
wget https://github.com/curimit/PaoPaoGateWay/releases/latest/download/user-data.yaml \
  -O /var/lib/vz/snippets/ppgw-user-data.yaml
vi /var/lib/vz/snippets/ppgw-user-data.yaml
```

## 2. 创建虚拟机

```bash
# 下载 Ubuntu 24.04 cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# 创建 VM(VMID 以 9100 为例,按需调整内存/网桥)
qm create 9100 --name paopao-gateway --memory 1024 --cores 2 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --ostype l26

# 导入磁盘并扩容
qm set 9100 --scsi0 local-lvm:0,import-from=$(pwd)/noble-server-cloudimg-amd64.img
qm disk resize 9100 scsi0 +4G

# 挂 cloud-init 盘并指定 user-data
qm set 9100 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket
qm set 9100 --cicustom "user=local:snippets/ppgw-user-data.yaml"

# 如需静态 IP(否则默认 DHCP):
# qm set 9100 --ipconfig0 ip=192.168.1.4/24,gw=192.168.1.1

qm start 9100
```

## 3. 首次启动

首次开机会自动安装依赖、下载运行时载荷,然后自动重启一次。重启完成后:

- VGA/串口控制台可看到 PaoPaoGW 横幅与运行日志
- 浏览器访问 `http://<VM_IP>/ui` 打开管理面板

> 注意:`--ipconfig0` 的静态 IP 由 cloud-init 首次写入 netplan,本项目安装时会以 `/etc/netplan/99-ppgw.yaml` 接管网络配置;如需静态 IP,建议直接修改该文件。
