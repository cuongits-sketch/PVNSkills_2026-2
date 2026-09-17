### Bổ sung trong file fw-setup.sh
##### ạn cần tạo public key tương ứng: id_ed25519.pub (dùng cho WireGuard) để copy sang các máy con (int-srv01, jamie-pvns01, ha-prx01/02, web01/02)
ssh-keygen -y -f /root/.ssh/id_ed25519 > /root/.ssh/id_ed25519.pub

### Cấu hình authorized_keys trên fw
### Để SSH từ máy client đến fw hoạt động, public key của client phải được đưa vào /root/.ssh/authorized_keys trên fw.

echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIByT0y8X9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v9v nine" >> /root/.ssh/authorized_keysmkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

### Sau đó cộng public key vào:

cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
