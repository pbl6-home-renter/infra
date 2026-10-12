#!/bin/bash
set -e

# ==============================================================================
# Script: setup-swap.sh
# Purpose: Cấu hình 2GB Swap Memory cho EC2 t3.micro (1GB RAM) chống lỗi OOM
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[-] Vui lòng chạy script này với quyền sudo (sudo ./scripts/setup-swap.sh)"
  exit 1
fi

SWAP_FILE="/swapfile"

if [ -f "$SWAP_FILE" ]; then
    echo "[!] File $SWAP_FILE đã tồn tại. Kiểm tra swap hiện tại:"
    swapon --show
    free -h
    exit 0
fi

echo "[+] Bắt đầu tạo 2GB Swap File..."
fallocate -l 2G $SWAP_FILE
chmod 600 $SWAP_FILE
mkswap $SWAP_FILE
swapon $SWAP_FILE

# Cấu hình tự động mount swap khi reboot
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# Tối ưu thông số swappiness (10: ưu tiên dùng RAM thật trước khi đẩy sang swap)
sysctl vm.swappiness=10
if ! grep -q "vm.swappiness=10" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "[✓] Tạo Swap 2GB thành công! Thông tin bộ nhớ:"
free -h
