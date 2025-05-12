#!/bin/bash
set -e

# --- Input parameters ---
PLATFORM="$1"             # e.g. "aws", "virtualbox", "qemu", "vmware"
IMAGE_NAME="$2"           # e.g. "myimage.img"
BUCKET="$3"               # e.g. "my-bucket"
TMP_DIR="/tmp/packer-image"
MOUNT_DIR="/mnt/image"

mkdir -p "$TMP_DIR" "$MOUNT_DIR"

echo ">> Downloading image: $IMAGE_NAME from s3://$BUCKET"
aws s3 cp "s3://$BUCKET/$IMAGE_NAME" "$TMP_DIR/$IMAGE_NAME"

# --- Platform-specific logic ---
case "$PLATFORM" in
  aws|qemu|raw)
    echo ">> Using qemu-nbd for $PLATFORM image..."
    sudo modprobe nbd max_part=8
    sudo qemu-nbd --connect=/dev/nbd0 "$TMP_DIR/$IMAGE_NAME"
    sleep 3
    sudo mount /dev/nbd0p1 "$MOUNT_DIR"
    ;;

  virtualbox|vmdk)
    echo ">> Mounting VMDK using guestmount..."
    sudo guestmount -a "$TMP_DIR/$IMAGE_NAME" -i "$MOUNT_DIR"
    ;;

  iso|vmware|ova)
    echo ">> Unsupported for direct editing. You may need to convert first."
    exit 1
    ;;

  *)
    echo ">> Unknown platform: $PLATFORM"
    exit 1
    ;;
esac

# --- Modify the image ---
echo ">> Injecting config..."
sudo chroot "$MOUNT_DIR" bash -c "echo 'Configured by Packer on $(date)' > /root/packer.txt"

# --- Cleanup ---
echo ">> Unmounting..."
case "$PLATFORM" in
  aws|qemu|raw)
    sudo umount "$MOUNT_DIR"
    sudo qemu-nbd --disconnect /dev/nbd0
    ;;
  virtualbox|vmdk)
    sudo guestunmount "$MOUNT_DIR"
    ;;
esac

# --- Upload modified image ---
echo ">> Uploading back to s3://$BUCKET"
aws s3 cp "$TMP_DIR/$IMAGE_NAME" "s3://$BUCKET/$IMAGE_NAME"

echo "✅ Done: $IMAGE_NAME for $PLATFORM modified and uploaded."
