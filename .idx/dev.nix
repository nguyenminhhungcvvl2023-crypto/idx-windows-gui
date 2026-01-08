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
      # CLEAN (DÙNG Ổ MỚI 100%)
      # =========================
      rm -rf /home/user/qemu /home/user/noVNC || true

      # =========================
      # PATHS
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/windows.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"

      OVMF_DIR="$VM_DIR/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$OVMF_DIR" "$VM_DIR"

      # =========================
      # OVMF (UEFI)
      # =========================
      wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

      # =========================
      # WINDOWS ISO (TINY11 – LINK BẠN ĐƯA)
      # =========================
      wget -O "$WIN_ISO" \
        "https://archive.org/download/tiny-11-NTDEV/tiny11%20b1.iso"

      # =========================
      # VIRTIO DRIVERS
      # =========================
      wget -O "$VIRTIO_ISO" \
        https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso

      # =========================
      # noVNC
      # =========================
      git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"

      # =========================
      # CREATE NEW DISK (Ổ MỚI)
      # =========================
      qemu-img create -f qcow2 "$RAW_DISK" 7G

      # =========================
      # START QEMU (28GB RAM)
      # =========================
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -smp 8,cores=8 \
        -M q35 \
        -m 28672 \
        -device usb-tablet \
        -vga virtio \
        -net nic,netdev=n0,model=virtio-net-pci \
        -netdev user,id=n0 \
        -boot d \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -cdrom "$WIN_ISO" \
        -drive file="$VIRTIO_ISO",media=cdrom \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # START noVNC
      # =========================
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # =========================
      # START CLOUDFLARED
      # =========================
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10
      grep -o "https://.*trycloudflare.com" /tmp/cloudflared.log | head -n1 > /home/user/noVNC-URL.txt

      # =========================
      # KEEP ALIVE
      # =========================
      while true; do sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [ "bash" "-lc" "echo 'noVNC running on port 8888'" ];
      };
      terminal = {
        manager = "web";
        command = [ "bash" ];
      };
    };
  };
}
