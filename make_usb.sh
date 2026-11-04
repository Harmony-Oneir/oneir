#!/bin/bash
# Подготовка загрузочной флешки oneir (UEFI + GRUB).
# Использование: sudo ./make_usb.sh /dev/sdX
set -e
DEV="$1"
ROOT_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
KERNEL="$ROOT_DIR/out/kernel/OBJ/linux-6.6/arch/x86/boot/bzImage"
ROOTIMG="$ROOT_DIR/out/oneir/ohos-root.img"
MNT=/tmp/oneir-usb

[[ $EUID -eq 0 ]] || { echo "Запустите от root"; exit 1; }
[[ -b "$DEV" ]] || { echo "Нет блочного устройства: $DEV"; exit 1; }

# Защита: только USB-устройство и без смонтированных разделов
[[ "$(lsblk -dno TRAN "$DEV")" == "usb" ]] || { echo "$DEV не USB-устройство, отказ"; exit 1; }
if lsblk -no MOUNTPOINT "$DEV" | grep -q .; then echo "На $DEV есть смонтированные разделы, отказ"; exit 1; fi
lsblk -o NAME,SIZE,MODEL,TRAN "$DEV"
read -r -p "ВСЕ ДАННЫЕ на $DEV будут удалены. Введите YES: " ok
[[ "$ok" == "YES" ]] || exit 1

for f in "$KERNEL" "$ROOTIMG"; do [[ -f "$f" ]] || { echo "Нет файла: $f"; exit 1; }; done

# Разметка GPT
wipefs -a "$DEV"
sgdisk -Z "$DEV"
sgdisk -n1:0:+256M -t1:ef00 -c1:esp \
       -n2:0:+4G   -t2:8300 -c2:system \
       -n3:0:0     -t3:8300 -c3:userdata "$DEV"
partprobe "$DEV"; sleep 2
P=$DEV; [[ "$DEV" =~ [0-9]$ ]] && P="${DEV}p"

# Файловые системы
mkfs.vfat -F32 -n ESP "${P}1"
dd if="$ROOTIMG" of="${P}2" bs=4M conv=fsync status=progress
e2fsck -fy "${P}2" || true
resize2fs "${P}2"
mkfs.ext4 -q -F -L userdata "${P}3"

ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${P}2")

# Загрузчик и ядро
mkdir -p "$MNT"; mount "${P}1" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true' EXIT
grub-install --target=x86_64-efi --removable --no-nvram \
             --efi-directory="$MNT" --boot-directory="$MNT/boot"
cp "$KERNEL" "$MNT/bzImage"

cat > "$MNT/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

menuentry "Oneir (OpenHarmony)" {
    linux /bzImage root=PARTUUID=$ROOT_PARTUUID rootwait rw selinux=0 hardware=x86_64_oneir_usb init=/system/bin/init console=ttyS0 console=tty0
}

menuentry "Oneir (OpenHarmony), отладка: все сообщения ядра" {
    linux /bzImage root=PARTUUID=$ROOT_PARTUUID rootwait rw selinux=0 hardware=x86_64_oneir_usb init=/system/bin/init console=ttyS0 console=tty0 loglevel=7 ignore_loglevel
}
EOF

sync
echo "Готово: $DEV (system PARTUUID=$ROOT_PARTUUID)"
