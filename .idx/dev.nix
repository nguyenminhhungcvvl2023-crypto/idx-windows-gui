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
    export HOME=/home/user
    cd "$HOME"

    echo "🧹 Cleaning VM folders only..."
    rm -rf "$HOME/qemu" "$HOME/noVNC"

    VM_DIR="$HOME/qemu"
    DISK="$VM_DIR/ws2025.qcow2"
    WIN_ISO="$VM_DIR/ws2025.iso"
    VIRTIO_ISO="$VM_DIR/virtio-win.iso"
    NOVNC_DIR="$HOME/noVNC"

    OVMF_DIR="$VM_DIR/ovmf"
    OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
    OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

    mkdir -p "$VM_DIR" "$OVMF_DIR"

    wget -nc -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
    wget -nc -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

    wget -nc -O "$WIN_ISO" "https://go.microsoft.com/fwlink/?linkid=2273506"
    wget -nc -O "$VIRTIO_ISO" \
      https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso

    qemu-img create -f qcow2 "$DISK" 6G

    git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"

    nohup qemu-system-x86_64 \
      -enable-kvm \
      -machine q35 \
      -cpu host \
      -smp 8 \
      -m 28672 \
      -vga virtio \
      -netdev user,id=n0 \
      -device virtio-net-pci,netdev=n0 \
      -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
      -drive if=pflash,format=raw,file="$OVMF_VARS" \
      -drive file="$DISK",if=virtio,format=qcow2 \
      -cdrom "$WIN_ISO" \
      -drive file="$VIRTIO_ISO",media=cdrom \
      -vnc :0 \
      -display none \
      > /tmp/qemu.log 2>&1 &

    nohup "$NOVNC_DIR/utils/novnc_proxy" \
      --vnc 127.0.0.1:5900 \
      --listen 8888 \
      > /tmp/novnc.log 2>&1 &

    nohup cloudflared tunnel \
      --no-autoupdate \
      --url http://localhost:8888 \
      > /tmp/cloudflared.log 2>&1 &

    sleep 10
    grep -o "https://.*trycloudflare.com" /tmp/cloudflared.log | head -n1 > "$HOME/noVNC-URL.txt"

    while true; do sleep 60; done
  '';
}
