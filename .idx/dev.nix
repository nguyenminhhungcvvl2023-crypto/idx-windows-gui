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
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/windows.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"

      OVMF_DIR="$HOME/qemu/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$OVMF_DIR" "$VM_DIR"

      # =========================
      # Full cleanup
      # =========================
      echo "💥 Cleaning old workspace..."
      rm -rf "$VM_DIR"/*
      rm -rf "$NOVNC_DIR"
      echo "✅ Cleanup done"

      # =========================
      # Download OVMF firmware
      # =========================
      echo "Downloading OVMF firmware..."
      wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

      # =========================
      # Download Windows ISO (Microsoft)
      # =========================
      echo "Downloading Windows ISO from Microsoft..."
      wget -O "$WIN_ISO" "https://go.microsoft.com/fwlink/?linkid=2273506"

      # =========================
      # Download VirtIO drivers ISO
      # =========================
      echo "Downloading VirtIO drivers ISO..."
      wget -O "$VIRTIO_ISO" \
        https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso

      # =========================
      # Clone noVNC
      # =========================
      echo "Cloning noVNC..."
      git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"

      # =========================
      # Create fresh QCOW2 disk
      # =========================
      echo "Creating new QCOW2 disk..."
      qemu-img create -f qcow2 "$RAW_DISK" 11G

      # =========================
      # Start QEMU (UEFI + VirtIO + KVM)
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
        -boot d \
        -device virtio-serial-pci \
        -device virtio-rng-pci \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -cdrom "$WIN_ISO" \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -uuid $(uuidgen) \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # Start noVNC on port 8888
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
