# Personal Config File for Intel 265K System with Intel GPU + Lanzaboote Secureboot w/ TPM LUKS unlock

# Install
Formatt disk into 2 partitions: /boot and /. Ensure you have the following subvolumes created:
```
btrfs subvolume create root
btrfs subvolume create clean-root
btrfs subvolume create nix
btrfs subvolume create persistent

nixos-generate-config --root /etc/nixos/
cd /etc/nixos/
git init
git add
nixos-install --flake .#nixos
```


This requires you to already have generated the keys and enrolled them with `sbctl`.

To create keys use `sbctl create-keys`.

```
nix-shell -p sbctl
sudo sbctl create-keys
```

To enroll them first reset secure boot to “Setup Mode”. This is device specific. Then enroll them using `sbctl enroll-keys -m -f`.

You can now rebuild your system with this option enabled.

Afterwards turn setup mode off and enable secure boot.

```
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p1
sudo systemd-cryptenroll /dev/nvme0n1p1 --tpm2-device=auto --tpm2-pcrs=0+2+7
```

# RECOVERY/INSTALL

```
cryptsetup /dev/mapper/enc /mnt
cd /mnt

# Delete the old system root (if it exists) to start fresh
# Create the fresh subvolumes
btrfs subvolume create root
btrfs subvolume create clean-root
btrfs subvolume create nix
btrfs subvolume create persistent
umount /mnt
```
Step 2: Mount Targets for Installation

Now we mount the subvolumes into /mnt so the installer knows where to put files.

# 1. Mount Root
```
mount -o subvol=root,compress=zstd /dev/mapper/enc /mnt
```
# 2. Create Mountpoints
```
mkdir -p /mnt/{nix,persistent,boot}
```
# 3. Mount the Rest
```
mount -o subvol=home,compress=zstd /dev/mapper/enc /mnt/home
mount -o subvol=nix,compress=zstd,noatime /dev/mapper/enc /mnt/nix
mount -o subvol=persistent,compress=zstd /dev/mapper/enc /mnt/persistent
```
# 4. Mount Boot Partition
```
mount /dev/nvme0n1p2 /mnt/boot
```

Step 4: Install

Run the install command using your flake.

```
cd /mnt/etc/nixos
nixos-generate-config --root /mnt
git init
git add .
nixos-install --flake .#nixos
```
