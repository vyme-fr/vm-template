qm create 200000 --name debian-12 --net0 virtio,bridge=vmbr0,tag=99,firewall=1 --scsihw virtio-scsi-pci
qm set 200000 --scsi0 local:0,iothread=1,backup=on,cache=writeback,format=qcow2,import-from=/root/debian-12-generic-amd64.qcow2
qm set 200000 --boot order=scsi0 --onboot 1
qm set 200000 --cpu host --cores 2 --memory 2048
qm set 200000 --ide2 local:cloudinit
qm set 200000 --agent enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1
qm set 200000 --nameserver "45.88.180.254"
qm template 200000
