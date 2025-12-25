cryptsetup luksFormat /dev/sda2
cryptsetup open "/dev/sda2 enc
#Create Filesystems
mkfs.fat -F32 "$disk""p1"
mkfs.btrfs -L nixos /dev/mapper/enc
mount "$disk""p2" /mnt
mkdir -p /mnt/boot
mount "$disk""p1" /mnt/boot
mkdir -p /mnt/etc/nixos
nix-channel --add https://nixos.org/channels/nixos-unstable nixos
nix-channel --update
nixos-generate-config --root /mnt
nixos-install  /mnt/etc/nixos/configuration.nix --no-root-password