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

  idx.workspace.onStart.qemu = ''
    set -e

    # =========================
    # FORCE STORAGE ON /home (sdc - persistent)
    # =========================
    export HOME=/home/user

    VM_DIR="$HOME/qemu"
    DISK="$VM_DIR/windows_server_2025.qcow2"
    WIN_ISO="$VM_DIR/windows_server_2025.iso"
    VIRTIO_ISO="$VM_DIR/virtio-win.iso"
    NOVNC_DIR="$HOME/noVNC"

    OVMF_DIR="$VM_DIR/ovmf"
    OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
    OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

    mkdir -p "$VM_DIR" "$OVMF_DIR"

    # =========================
    # OVMF (UEFI)
    # =========================
    if [ ! -f "$OVMF_CODE" ]; then
      wget -O "$OVMF_CODE" \
        https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
    fi

    if [ ! -f "$OVMF_VARS" ]; then
      wget -O "$OVMF_VARS" \
        https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
    fi

    # =========================
    # Windows Server 2025 ISO (Microsoft fwlink)
    # =========================
    if [ ! -f "$WIN_ISO" ]; then
      echo "Downloading Windows Server 2025 ISO..."
      wget -O "$WIN_ISO" \
        "https://go.microsoft.com/fwlink/?linkid=2293312&clcid=0x409&culture=en-us&country=us"
    else
      echo "Windows Server 2025 ISO already exists."
    fi

    # =========================
    # VirtIO Drivers
    # =========================
    if [ ! -f "$VIRTIO_ISO" ]; then
      wget -O "$VIRTIO_ISO" \
        https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
    fi

    # =========================
    # Create disk (50G for Server)
    # =========================
    if [ ! -f "$DISK" ]; then
      qemu-img create -f qcow2 "$DISK" 50G
    fi

    # =========================
    # Clone noVNC
    # =========================
    if [ ! -d "$NOVNC_DIR/.git" ]; then
      git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
    fi

    # =========================
    # Start QEMU (UEFI + VirtIO)
    # =========================
    echo "Starting Windows Server 2025 VM..."

    nohup qemu-system-x86_64 \
      -enable-kvm \
      -machine q35 \
      -cpu host \
      -smp 8 \
      -m 28672 \
      -device virtio-balloon-pci \
      -device virtio-rng-pci \
      -vga virtio \
      -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
      -device virtio-net-pci,netdev=n0 \
      -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
      -drive if=pflash,format=raw,file="$OVMF_VARS" \
      -drive file="$DISK",if=virtio,format=qcow2 \
      -cdrom "$WIN_ISO" \
      -drive file="$VIRTIO_ISO",media=cdrom \
      -vnc :0 \
      -display none \
      > /tmp/qemu.log 2>&1 &

    # =========================
    # noVNC
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
      echo "===================================="
      echo " 🌍 Windows Server 2025 ready:"
      echo " $URL/vnc.html"
      echo "$URL/vnc.html" > "$HOME/noVNC-URL.txt"
      echo "===================================="
    else
      echo "❌ Cloudflared failed"
    fi

    # =========================
    # Keep workspace alive
    # =========================
    while true; do
      sleep 60
    done
  '';
}
