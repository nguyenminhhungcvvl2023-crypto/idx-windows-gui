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
      # Cleanup (one-time)
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
      WIN_ISO="$VM_DIR/windows.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"

      OVMF_DIR="$VM_DIR/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$VM_DIR" "$OVMF_DIR"

      # =========================
      # OVMF
      # =========================
      [ -f "$OVMF_CODE" ] || wget -O "$OVMF_CODE" \
        https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd

      [ -f "$OVMF_VARS" ] || wget -O "$OVMF_VARS" \
        https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd

      # =========================
      # Windows ISO (MỚI)
      # =========================
      if [ ! -f "$WIN_ISO" ]; then
        wget -O "$WIN_ISO" \
          https://archive.org/download/tiny-11-NTDEV/tiny11%20b1.iso
      fi

      # =========================
      # VirtIO ISO
      # =========================
      if [ ! -f "$VIRTIO_ISO" ]; then
        wget -O "$VIRTIO_ISO" \
          https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # =========================
      # noVNC
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # =========================
      # TẠO Ổ CỨNG MỚI 100%
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        qemu-img create -f qcow2 "$RAW_DISK" 7G
      fi

      # =========================
      # START QEMU
      # =========================
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
      # Cloudflare
      # =========================
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      while true; do sleep 60; done
    '';
  };
}
