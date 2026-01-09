{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # ==========================================
      # 1. DỌN DẸP SẠCH SẼ (Cứu vớt từng MB ổ cứng)
      # ==========================================
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* /home/user/.cache/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-windows-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # ==========================================
      # 2. CẤU HÌNH
      # ==========================================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      
      # Link tải bản Win rút gọn (Tiny 11) - Chỉ 3GB
      ISO_URL="https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso"
      WIN_ISO="$VM_DIR/automic11.iso"

      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      
      OVMF_DIR="$HOME/qemu/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$OVMF_DIR"
      mkdir -p "$VM_DIR"

      # ==========================================
      # 3. TẢI BIOS & DRIVER
      # ==========================================
      if [ ! -f "$OVMF_CODE" ]; then
         wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      fi
      if [ ! -f "$OVMF_VARS" ]; then
         wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
      fi
      if [ ! -f "$VIRTIO_ISO" ]; then
        echo "Downloading VirtIO drivers..."
        wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # ==========================================
      # 4. CHUẨN BỊ BỘ CÀI WINDOWS (ISO)
      # ==========================================
      if [ ! -f "$WIN_ISO" ]; then
        echo "⬇️ Dang tai Tiny 11 ISO (3GB)..."
        wget -O "$WIN_ISO" "$ISO_URL"
      fi

      # Tạo ổ cứng ảo mới tinh (15GB nhưng rỗng, chưa tốn dung lượng)
      if [ ! -f "$RAW_DISK" ]; then
        echo "💿 Tao o cung ao moi..."
        qemu-img create -f qcow2 "$RAW_DISK" 15G
      fi

      # ==========================================
      # 5. CÀI ĐẶT NOVNC
      # ==========================================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        mkdir -p "$NOVNC_DIR"
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # ==========================================
      # 6. KHỞI ĐỘNG (BOOT TỪ ĐĨA CÀI ĐẶT)
      # ==========================================
      echo "🚀 Starting QEMU Installer..."
      
      # Logic Boot:
      # Lần đầu: Boot từ CD ($WIN_ISO) để cài Win (-boot d)
      # Cài xong: Bro tắt đi bật lại, sửa dòng -boot d thành -boot c là vào Win
      
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,+pae,+nx,kvm=on,+svm \
        -smp 6,cores=6 \
        -M q35,usb=on \
        -device usb-tablet \
        -m 28G \
        -device virtio-balloon-pci \
        -vga virtio \
        -net nic,netdev=n0,model=virtio-net-pci \
        -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
        -boot d \
        -device virtio-serial-pci \
        -device virtio-rng-pci \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -drive file="$WIN_ISO",media=cdrom,if=ide \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -uuid e47ddb84-fb4d-46f9-b531-14bb15156336 \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # ==========================================
      # 7. KẾT NỐI
      # ==========================================
      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 > /tmp/novnc.log 2>&1 &

      echo "Starting Cloudflared..."
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log 2>&1 &

      sleep 10
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================================"
        echo "👉 VAO DAY DE CAI WIN: $URL/vnc.html"
        echo "========================================================"
        echo "LINK: $URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
      fi

      while true; do sleep 60; done
    '';
  };
  
  idx.previews = {
    enable = true;
    previews = {
      qemu_status = {
        manager = "web";
        command = [ "bash" "-lc" "tail -f /tmp/qemu.log" ];
      };
    };
  };
}
