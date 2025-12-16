#!/usr/bin/env bash
set -xeuo pipefail

CONFIG="config.yml"
IMAGES="images.yml"

require() {
  command -v "$1" >/dev/null || {
    echo "Missing dependency: $1"
    exit 1
  }
}

require yq
require wget
require virt-customize
require qm

echo "OS list:"
yq '.images | keys' "$IMAGES"

read -rp "OS (debian/ubuntu): " OS
read -rp "Version: " VERSION

IMAGE_URL=$(yq ".images.$OS.\"$VERSION\".url" "$IMAGES")
[ "$IMAGE_URL" = "null" ] && { echo "❌ Unknown OS/version"; exit 1; }

IMAGE_FILE=$(basename "$IMAGE_URL") 

echo "Downloading $IMAGE_FILE"
wget -q --show-progress $IMAGE_URL

CONVERT_POLICY=$(yq -r '.image.convert_qcow2_to_raw // "true"' "$CONFIG")

if [[ "$IMAGE_FILE" == *.qcow2 && "$CONVERT_POLICY" == "true" ]]; then
  RAW_IMAGE="${IMAGE_FILE%.qcow2}.raw"

  echo "Converting qcow2 to raw"
  qemu-img convert -p -O raw "$IMAGE_FILE" "$RAW_IMAGE"

  IMAGE_FILE="$RAW_IMAGE"
fi

### virt-customize
INSTALL_PKGS=$(yq -r '.virt_custom.install | join(",")' "$CONFIG")

CMD_ARGS=()
for cmd in $(yq -r '.virt_custom.commands[]' "$CONFIG"); do
  CMD_ARGS+=(--run-command "$cmd")
done

COPY_COUNT=$(yq '.virt_custom.copy | length' "$CONFIG")
for ((i=0; i<COPY_COUNT; i++)); do
  SRC=$(yq -r ".virt_custom.copy[$i].src" "$CONFIG")
  DST=$(yq -r ".virt_custom.copy[$i].dst" "$CONFIG")
  MODE=$(yq -r ".virt_custom.copy[$i].mode" "$CONFIG")

  CMD_ARGS+=(--copy-in "$SRC:$DST")
  [ "$MODE" != "null" ] && CMD_ARGS+=(--run-command "chmod $MODE $DST")
done

FIRSTBOOT=$(yq -r '.firstboot[]' "$CONFIG")

echo "virt-customize"
virt-customize \
  -a "$IMAGE_FILE" \
  --install "$INSTALL_PKGS" \
  "${CMD_ARGS[@]}" \
  --firstboot-command "$FIRSTBOOT"

### Proxmox
VMID=$(yq '.template.vmid' "$CONFIG")
NAME_PREFIX=$(yq -r '.template.name_prefix' "$CONFIG")
NAME="${NAME_PREFIX}-${OS}-${VERSION}"

BRIDGE=$(yq -r '.template.bridge' "$CONFIG")
VLAN=$(yq '.template.vlan' "$CONFIG")
NS=$(yq -r '.template.nameserver' "$CONFIG")
STORAGE=$(yq -r '.template.storage' "$CONFIG")

CORES=$(yq '.resources.cores' "$CONFIG")
MEMORY=$(yq '.resources.memory' "$CONFIG")
CPU=$(yq -r '.resources.cpu' "$CONFIG")

echo "Creating VM $VMID ($NAME)"

qm create "$VMID" \
  --name "$NAME" \
  --net0 virtio,bridge="$BRIDGE",tag="$VLAN",firewall=1 \
  --scsihw virtio-scsi-single

qm set "$VMID" \
  --virtio0 "$STORAGE":0,import-from="$PWD/$IMAGE_FILE",iothread=1,backup=on,cache=writeback \
  --boot order=virtio0 \
  --onboot 1 \
  --cpu "$CPU" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --ide2 "$STORAGE":cloudinit \
  --agent enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1 \
  --serial0 socket \
  --vga serial0 \
  --nameserver "$NS"

qm template "$VMID"

echo "Proxmox template is ready: $NAME"