#!/usr/bin/env bash
set -euo pipefail

CONFIG="config.yml"
IMAGES="images.yml"

#######################################
# Utils
#######################################
require() {
  command -v "$1" >/dev/null || {
    echo "Missing dependency: $1"
    exit 1
  }
}

die() {
  echo "$1"
  exit 1
}

#######################################
# Deps
#######################################
require yq
require wget
require virt-customize
require qm
require qemu-img
require pvesm

#######################################
# Select OS / version
#######################################
echo "OS list:"
yq -r '.images | keys[]' "$IMAGES"

read -rp "OS (debian/ubuntu): " OS
read -rp "Version: " VERSION

IMAGE_URL=$(yq -r ".images.$OS.\"$VERSION\".url" "$IMAGES")
[ -z "$IMAGE_URL" ] && die "Unknown OS/version"

IMAGE_FILE=$(basename "$IMAGE_URL")

#######################################
# Download
#######################################
echo "Downloading $IMAGE_FILE"
wget -q --show-progress "$IMAGE_URL"

[ -s "$IMAGE_FILE" ] || die "Download failed (empty file)"

#######################################
# Optional qcow2 → raw conversion
#######################################
CONVERT_POLICY=$(yq -r '.image.convert_qcow2_to_raw // "auto"' "$CONFIG")
STORAGE=$(yq -r '.template.storage' "$CONFIG")

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR==2 {print $2}')
SHOULD_CONVERT=0

case "$CONVERT_POLICY" in
  true)
    SHOULD_CONVERT=1
    ;;
  false)
    SHOULD_CONVERT=0
    ;;
  auto)
    [ "$STORAGE_TYPE" = "dir" ] && SHOULD_CONVERT=1
    ;;
  *)
    die "Invalid convert_qcow2_to_raw value: $CONVERT_POLICY"
    ;;
esac

if [[ "$IMAGE_FILE" == *.qcow2 && "$SHOULD_CONVERT" -eq 1 ]]; then
  RAW_IMAGE="${IMAGE_FILE%.qcow2}.raw"
  echo "Converting qcow2 → raw (policy=$CONVERT_POLICY, storage=$STORAGE_TYPE)"
  qemu-img convert -p -O raw "$IMAGE_FILE" "$RAW_IMAGE"
  IMAGE_FILE="$RAW_IMAGE"
fi

#######################################
# virt-customize
#######################################
INSTALL_PKGS=$(yq -r '.virt_custom.install | join(",")' "$CONFIG")

CMD_ARGS=()

# run-command (SAFE loop)
while IFS= read -r cmd; do
  CMD_ARGS+=(--run-command "$cmd")
done < <(yq -r '.virt_custom.commands[]' "$CONFIG")

# copy-in
COPY_COUNT=$(yq -r '.virt_custom.copy | length // 0' "$CONFIG")

for ((i=0; i<COPY_COUNT; i++)); do
  SRC=$(yq -r ".virt_custom.copy[$i].src" "$CONFIG")
  DST=$(yq -r ".virt_custom.copy[$i].dst" "$CONFIG")
  MODE=$(yq -r ".virt_custom.copy[$i].mode // \"\"" "$CONFIG")

  CMD_ARGS+=(--copy-in "$SRC:$DST")
  [ -n "$MODE" ] && CMD_ARGS+=(--run-command "chmod $MODE $DST")
done

FIRSTBOOT_CMD=$(yq -r '.firstboot | join(" && ")' "$CONFIG")

echo "virt-customize"
virt-customize \
  -a "$IMAGE_FILE" \
  --install "$INSTALL_PKGS" \
  "${CMD_ARGS[@]}" \
  --firstboot-command "$FIRSTBOOT_CMD"

#######################################
# Proxmox VM
#######################################
VMID=$(yq -r '.template.vmid' "$CONFIG")
NAME_PREFIX=$(yq -r '.template.name_prefix' "$CONFIG")
NAME="${NAME_PREFIX}-${OS}-${VERSION}"

BRIDGE=$(yq -r '.template.bridge' "$CONFIG")
VLAN=$(yq -r '.template.vlan' "$CONFIG")
NS=$(yq -r '.template.nameserver' "$CONFIG")

CORES=$(yq -r '.resources.cores' "$CONFIG")
MEMORY=$(yq -r '.resources.memory' "$CONFIG")
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

echo "Proxmox template ready: $NAME"