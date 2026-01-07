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

    echo "🧹 Cleaning /home (sdc user storage)..."
    rm -rf /home/user/*
    rm -rf /home/user/.[!.]* /home/user/.??* || true

    VM_DIR="$HOME/qemu"
    DISK="$VM_DIR/windows_server_2025.qcow2"
    WIN_ISO="$VM_DIR/windows_server_2025.iso"
    VIRTIO_ISO="$VM_DIR/virtio-win.iso"
    NOVNC_DIR="$HOME/noVNC"

    OVMF_DIR="$VM_DIR/ovmf"
    OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
    OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

    mkdir -p "$VM_DIR" "$OVMF_DIR"

    echo "📦 Downloading OVMF..."
    wget -nc -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
    wget -nc -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

    echo "📀 Downloading Windows Server 2025 ISO..."
    wget -nc -O "$WIN_ISO" "https://go.microsoft.com/fwlink/?linkid=2273506"

    echo "📀 Downloading VirtIO drivers..."
    wget -nc -O "$VIRTIO_ISO" \
      https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso

    echo "📊 Calculating disk size = free(/home) - 10GB"
    FREE_GB=$(df -BG /home | awk 'NR==2 {gsub("G","",$4); print $4}')
    DISK_GB=$((FREE_GB - 10))

    if [ "$DISK_GB" -le 5 ]; then
      echo "❌ Not enough disk space"
      exit 1
    fi

    echo "💽 Creating disk size: $DISK_GB GB"
    qemu-img create -f qcow2 "$DISK" "$DISK_GB"G

    echo "🌐 Cloning noVNC..."
    git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"

    echo "🚀 Starting Windows Server 2025 (RAM 28G / CPU 8)..."
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

    echo "🖥 Starting noVNC..."
    nohup "$NOVNC_DIR/utils/novnc_proxy" \
      --vnc 127.0.0.1:5900 \
      --listen 8888 \
      > /tmp/novnc.log 2>&1 &

    echo "🌍 Starting Cloudflared..."
    nohup cloudflared tunnel \
      --no-autoupdate \
      --url http://localhost:8888 \
      > /tmp/cloudflared.log 2>&1 &

    sleep 10

    grep -o "https://.*trycloudflare.com" /tmp/cloudflared.log | head -n1 > "$HOME/noVNC-URL.txt"

    while true; do sleep 60; done
  '';
}
