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
    pkgs.unrar  # <--- QUAN TRỌNG: Thêm cái này để giải nén file RAR
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # =========================
      # Dọn dẹp môi trường cũ
      # =========================
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-windows-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # =========================
      # Cấu hình đường dẫn
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      RAR_FILE="$VM_DIR/windows.rar"
      
      # Link tải file RAR của bro
      DOWNLOAD_URL="https://drive.usercontent.google.com/download?id=1ohHQojU1jN0yDDt3piK1T501IfhVVweC&export=download&authuser=0"

      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      
      OVMF_DIR="$HOME/qemu/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$OVMF_DIR"
      mkdir -p "$VM_DIR"

      # =========================
      # 1. Tải BIOS UEFI
      # =========================
      if [ ! -f "$OVMF_CODE" ]; then
         wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      fi
      if [ ! -f "$OVMF_VARS" ]; then
         wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
      fi

      # =========================
      # 2. Xử lý tải và giải nén Windows RAR
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        echo "🔍 Kiem tra file Windows..."
        
        echo "⬇️ Dang tai file RAR tu Google Drive..."
        wget -O "$RAR_FILE" "$DOWNLOAD_URL"
        
        echo "📦 Dang giai nen file RAR..."
        # Giải nén vào thư mục qemu, -y là đồng ý đè nếu trùng
        unrar e -y "$RAR_FILE" "$VM_DIR/"
        
        echo "🧹 Dang xoa file RAR rac..."
        rm "$RAR_FILE"

        # Tự động tìm file .qcow2 vừa giải nén và đổi tên chuẩn
        # (Đề phòng file bên trong tên là abcxyz.qcow2)
        FOUND_FILE=$(find "$VM_DIR" -maxdepth 1 -name "*.qcow2" | head -n 1)
        if [ -n "$FOUND_FILE" ] && [ "$FOUND_FILE" != "$RAW_DISK" ]; then
            echo "🔄 Doi ten $FOUND_FILE thanh windows.qcow2"
            mv "$FOUND_FILE" "$RAW_DISK"
        fi
        
        echo "✅ Da co file o cung: $RAW_DISK"
      else
        echo "✅ File Windows.qcow2 da co san, bo qua tai."
      fi

      # =========================
      # 3. Tải Driver VirtIO (Để nhận mạng/chuột)
      # =========================
      if [ ! -f "$VIRTIO_ISO" ]; then
        echo "Downloading VirtIO drivers..."
        wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # =========================
      # 4. Cài noVNC
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        mkdir -p "$NOVNC_DIR"
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # =========================
      # 5. CHẠY MÁY ẢO (BOOT THẲNG)
      # =========================
      echo "🚀 Starting QEMU Windows..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,+pae,+nx,kvm=on,+svm \
        -smp 8,cores=8 \
        -M q35,usb=on \
        -device usb-tablet \
        -m 28G \
        -device virtio-balloon-pci \
        -vga virtio \
        -net nic,netdev=n0,model=virtio-net-pci \
        -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
        -boot c \
        -device virtio-serial-pci \
        -device virtio-rng-pci \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -uuid e47ddb84-fb4d-46f9-b531-14bb15156336 \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # 6. Kết nối hiển thị
      # =========================
      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 > /tmp/novnc.log 2>&1 &

      echo "Starting Cloudflared..."
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log 2>&1 &

      sleep 10
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "LINK TRUY CAP: $URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
      fi

      # Keep alive
      while true; do sleep 60; done
    '';
  };
  
  # Cấu hình Preview để xem log
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
