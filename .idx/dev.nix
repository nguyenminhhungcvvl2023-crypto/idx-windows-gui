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
    # FORCE STORAGE ON /home (sdc)
    # =========================
    export HOME=/home/user

    VM_DIR="$HOME/qemu"
    DISK="$VM_DIR/win-server-2025.qcow2"
    WIN_ISO="$VM_DIR/win-server-2025.iso"
    VIRTIO_ISO="$VM_DIR/virtio-win.iso"
    NOVNC_DIR="$HOME/noVNC"

    OVMF_DIR="$VM_DIR/ovmf"
    OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
    OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

    mkdir -p "$VM_DIR" "$OVMF_DIR"

    # =========================
    # OVMF
    # =========================
    [ ! -f "$OVMF_CODE" ] && wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
    [ ! -f "$OVMF_VARS" ] && wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

    # =========================
    # Windows Server 2025 ISO
    # =========================
    if [ ! -f "$WIN_ISO" ]; then
      echo "Download Windows Server 2025 ISO..."
      wget -O "$WIN_ISO" https://YOUR_WINDOWS_SERVER_2025_ISO_LINK.iso
    fi

    # =========================
    # VirtIO
    # =========================
    [ ! -f "$VIRTIO_ISO" ] && \
      wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso

    # =========================
    # Disk 40G
    # =========================
    [ ! -f "$DISK" ] && qemu-img create -f qcow2 "$DISK" 40G

    # =========================
    # noVNC
    # =========================
    if [ ! -d "$NOVNC_DIR/.git" ]; then
      git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
    fi

    # =========================
    # START QEMU
    # =========================
    nohup qemu-system-x86_64 \
      -enable-kvm \
      -cpu host \
      -smp 8 \
      -m 28672 \
      -machine q35 \
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
      -vnc :0 -display none \
      > /tmp/qemu.log 2>&1 &

    # =========================
    # noVNC + Cloudflare
    # =========================
    nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc localhost:5900 --listen 8888 &
    nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log &

    sleep 10
    grep -o "https://.*trycloudflare.com" /tmp/cloudflared.log | head -n1 > "$HOME/noVNC-URL.txt"

    while true; do sleep 60; done
  '';
}
