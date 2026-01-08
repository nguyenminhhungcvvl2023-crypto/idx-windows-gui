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
    pkgs.jq
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # =========================
      # Cleanup one-time
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
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/tiny11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      OVMF_DIR="$VM_DIR/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      DESIRED_QCOW2_SIZE=13G  # để tổng full ổ ~16GB

      mkdir -p "$VM_DIR" "$OVMF_DIR"

      # =========================
      # Download OVMF firmware
      # =========================
      [ -f "$OVMF_CODE" ] || wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      [ -f "$OVMF_VARS" ] || wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

      # =========================
      # Download Tiny11 ISO (~2GB)
      # =========================
      [ -f "$WIN_ISO" ] || wget -O "$WIN_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso

      # =========================
      # Download VirtIO ISO (~0.3GB)
      # =========================
      [ -f "$VIRTIO_ISO" ] || wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso

      # =========================
      # Clone noVNC
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # =========================
      # Create or resize QCOW2 disk
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        echo "Creating QCOW2 disk $DESIRED_QCOW2_SIZE..."
        qemu-img create -f qcow2 "$RAW_DISK" $DESIRED_QCOW2_SIZE
      else
        CURRENT_SIZE=$(qemu-img info --output=json "$RAW_DISK" | jq -r '.virtual-size')
        DESIRED_BYTES=$(numfmt --from=iec $DESIRED_QCOW2_SIZE)
        if [ "$CURRENT_SIZE" -lt "$DESIRED_BYTES" ]; then
          echo "Resizing existing QCOW2 disk to $DESIRED_QCOW2_SIZE..."
          qemu-img resize "$RAW_DISK" $DESIRED_QCOW2_SIZE
        fi
      fi

      # =========================
      # Start QEMU
      # =========================
      echo "Starting QEMU..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,+pae,+nx,kvm=on,+svm \
        -smp 8,cores=8 \
        -M q35,usb=on \
        -device usb-tablet \
        -m 28672 \
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
        -cdrom "$WIN_ISO" \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -uuid e47ddb84-fb4d-46f9-b531-14bb15156336 \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # Start noVNC
      # =========================
      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # =========================
      # Start Cloudflared tunnel
      # =========================
      echo "Starting Cloudflared tunnel..."
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Windows 11 QEMU + noVNC ready:"
        echo "     $URL/vnc.html"
        echo "     $URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed"
      fi

      # =========================
      # Keep workspace alive
      # =========================
      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [
          "bash" "-lc"
          "echo 'noVNC running on port 8888'"
        ];
      };
      terminal = {
        manager = "web";
        command = [ "bash" ];
      };
    };
  };
}
