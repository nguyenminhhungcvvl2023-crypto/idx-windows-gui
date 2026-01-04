
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

      # =========================
      # One-time cleanup (original logic)
      # =========================
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-ubuntu22-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # =========================
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.raw"
      WIN_ISO="$VM_DIR/automic11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"

      mkdir -p "$VM_DIR"
      mkdir -p "$NOVNC_DIR"

      # =========================
      # Download Windows ISO
      # =========================
      if [ ! -f "$WIN_ISO" ]; then
        wget -O "$WIN_ISO" \
          https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso
      fi

      # =========================
      # Download VirtIO drivers ISO
      # =========================
      if [ ! -f "$VIRTIO_ISO" ]; then
        wget -O "$VIRTIO_ISO" \
          https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.271-1/virtio-win.iso
      fi

      # =========================
      # Clone noVNC
      # =========================
      if [ -d "$NOVNC_DIR" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # =========================
      # Create RAW disk (11GB)
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        qemu-img create -f raw "$RAW_DISK" 11G
      fi

      # =========================
      # Start QEMU (KVM + VirtIO)
      # =========================
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -machine type=q35,accel=kvm \
        -cpu host \
        -m 28672 \
        -smp 8 \
        \
        -drive file="$RAW_DISK",format=raw,if=none,id=vdisk \
        -device virtio-blk-pci,drive=vdisk \
        \
        -drive file="$WIN_ISO",media=cdrom,if=none,id=cd1 \
        -device ide-cd,drive=cd1 \
        \
        -drive file="$VIRTIO_ISO",media=cdrom,if=none,id=cd2 \
        -device ide-cd,drive=cd2 \
        \
        -boot order=d \
        \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        \
        -device virtio-vga \
        \
        -vnc :0 \
        -display none \
        \
        > /tmp/qemu.log 2>&1 &

      sleep 10

      # =========================
      # Start noVNC (port 8888)
      # =========================
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # =========================
      # Cloudflared tunnel
      # =========================
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Windows QEMU + noVNC ready:"
        echo "     $URL"
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed"
      fi

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
    };
  };
}

