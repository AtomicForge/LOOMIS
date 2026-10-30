#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grub_config="$repo_root/prototype/grub/grub.cfg"

for command in grub2-mkstandalone qemu-system-x86_64 mktemp cp; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

if [[ ! -r "$grub_config" ]]; then
    printf 'GRUB configuration is not readable: %s\n' "$grub_config" >&2
    exit 1
fi

# Override these paths when the distribution stores OVMF elsewhere.
ovmf_code="${OVMF_CODE:-/usr/share/edk2/ovmf/OVMF_CODE.fd}"
ovmf_vars="${OVMF_VARS:-/usr/share/edk2/ovmf/OVMF_VARS.fd}"
for firmware in "$ovmf_code" "$ovmf_vars"; do
    if [[ ! -f "$firmware" || ! -r "$firmware" ]]; then
        printf 'OVMF firmware is not a readable file: %s\n' "$firmware" >&2
        printf 'Set OVMF_CODE and OVMF_VARS to a matching firmware pair.\n' >&2
        exit 1
    fi
done

test_dir="$(mktemp -d /tmp/loomis-uefi.XXXXXXXXXX)"
cleanup() {
    # Only remove the private directory created by mktemp above.
    if [[ -n "$test_dir" && "$test_dir" == /tmp/loomis-uefi.* ]]; then
        rm -rf -- "$test_dir"
    fi
}
trap cleanup EXIT
export TMPDIR="$test_dir"
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -p -- "$test_dir/esp/EFI/BOOT"
cp -- "$ovmf_code" "$test_dir/OVMF_CODE.fd"
cp -- "$ovmf_vars" "$test_dir/OVMF_VARS.fd"

grub2-mkstandalone \
    --format=x86_64-efi \
    --output="$test_dir/esp/EFI/BOOT/BOOTX64.EFI" \
    "boot/grub/grub.cfg=$grub_config"

# The guest receives only temporary files; host firmware is never writable.
# This automates setup and launch; inspect the GRUB success message visually.
qemu-system-x86_64 \
    -no-user-config \
    -machine q35 \
    -m 256 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$test_dir/OVMF_CODE.fd" \
    -drive "if=pflash,format=raw,unit=1,file=$test_dir/OVMF_VARS.fd" \
    -drive "format=raw,file=fat:rw:$test_dir/esp" \
    -nic none \
    -no-reboot
