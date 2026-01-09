{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.curl   # Dùng curl để pipe luồng ổn định hơn
    pkgs.git
    pkgs.python3
    pkgs.unrar  # Bắt buộc
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # ==========================================
      # 1. DỌN DẸP SẠCH SẼ (Cực quan trọng vì ổ đầy)
      # ==========================================
      if [ ! -f /home/user/.cleanup_done ]; then
        # Xóa cache gradle, android, mọi thứ rác có thể
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
      
      # Link Pixeldrain API
      DOWNLOAD_URL="https://pixeldrain.com/api/file/CfLHGhuE"

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
        wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # ==========================================
      # 4. STREAMING: VỪA TẢI VỪA GIẢI NÉN (Magic here!)
      # ==========================================
      if [ ! -f "$RAW_DISK" ]; then
        echo "⚠️  CANH BAO: O CUNG SAP HET CHO TRONG!"
        echo "🚀 Dang chay che do STREAMING: Tai -> Giai nen luon -> Ghi o cung"
        echo "⏳ Khong luu file RAR. Cho khoang 5-10 phut..."
        
        # GIẢI THÍCH LỆNH:
        # curl -L: Tải file
        # | : Chuyển dữ liệu sang lệnh sau ngay lập tức
        # unrar p -si: Đọc từ luồng (stdin) và in nội dung file giải nén ra màn hình
        # > "$RAW_DISK": Hứng nội dung đó ghi vào file qcow2
        
        curl -L "$DOWNLOAD_URL" | unrar p -si -inul > "$RAW_DISK"
        
        # Kiểm tra thành phẩm
        FILE_SIZE=$(stat -c%s "$RAW_DISK")
        if [ "$FILE_SIZE" -lt 1000000000 ]; then
           echo "❌ LOI: File tao ra qua nho. Co the loi mang hoac het bo nho."
           rm "$RAW_DISK"
           exit 1
        fi
        
        echo "✅ XONG! Da tao file o cung 12GB (Hy vong con du cho chay Win 😅)"
      else
        echo "✅ File Windows.qcow2 da co san."
      fi

      # ==========================================
      # 5. CÀI ĐẶT NOVNC
      # ==========================================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        mkdir -p "$NOVNC_DIR"
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # ==========================================
      # 6. KHỞI ĐỘNG QEMU
      # ==========================================
      echo "🚀 Starting QEMU Windows..."
      
      # Lưu ý: Vì RAM máy ảo IDX cũng có hạn, nên giảm RAM Win xuống 8GB (8192) cho an toàn
      # Nếu để 12GB như cũ có thể bị OOM (Out of Memory) crash
      
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,+pae,+nx,kvm=on,+svm \
        -smp 8,cores=8 \
        -M q35,usb=on \
        -device usb-tablet \
        -m 28679 \
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
        echo "LINK TRUY CAP: $URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
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
