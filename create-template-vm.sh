set -x
qm create 200000 --name debian-12 --net0 virtio,bridge=vmbr0,tag=99,firewall=1 --scsihw virtio-scsi-single
qm set 200000 --virtio0 local:0,iothread=1,backup=on,cache=writeback,format=raw,import-from=/root/debian-12-generic-amd64.raw
qm set 200000 --boot order=virtio0 --onboot 1
qm set 200000 --cpu host --cores 2 --memory 2048
qm set 200000 --ide2 local:cloudinit
qm set 200000 --agent enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1
qm set 200000 --serial0 socket --vga serial0
qm set 200000 --nameserver "45.88.180.254"
qm template 200000
