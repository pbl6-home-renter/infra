#!/bin/bash
set -e

echo "[+] Cập nhật package hệ thống..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release git

echo "[+] Thêm Docker GPG key và repo chính thức..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[+] Cài đặt Docker Engine và Docker Compose plugin..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[+] Cấp quyền chạy docker không cần sudo cho user '$USER'..."
sudo usermod -aG docker $USER

echo "[+] Kích hoạt Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

echo "[✓] Cài đặt Docker hoàn tất!"
docker --version
docker compose version
echo "[!] Lưu ý: Bạn cần đăng xuất (logout) SSH và đăng nhập lại để quyền nhóm docker có hiệu lực."
