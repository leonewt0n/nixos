{
  description = "Intel 265K System with Nvidia GPU + Lanzaboote Secureboot w/ TPM LUKS unlock";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
    lanzaboote = { url = "github:nix-community/lanzaboote/v1.0.0"; inputs.nixpkgs.follows = "nixpkgs"; };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    impermanence.url = "github:nix-community/impermanence";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    disko.url = "github:nix-community/disko";
    nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
    nixpkgs-wayland.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, lanzaboote, determinate,impermanence,nix-flatpak,nixpkgs-wayland,  ... } @ inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        lanzaboote.nixosModules.lanzaboote
        determinate.nixosModules.default
        home-manager.nixosModules.home-manager
        impermanence.nixosModules.impermanence
        nix-flatpak.nixosModules.nix-flatpak
        {
          nixpkgs.overlays = [ inputs.nixpkgs-wayland.overlays.default ];
        }
        {
          home-manager = { useGlobalPkgs = true; useUserPackages = true; extraSpecialArgs = { inherit inputs; }; };
        }
        ({ config, pkgs, lib, ... }: {
          imports = [ ./hardware-configuration.nix ];
          system.stateVersion = "26.05";
          nixpkgs.config.allowUnfree = true;

          nix.settings = { auto-optimise-store = true; eval-cores = 0; http-connections = 50; max-jobs = "auto"; extra-platforms = [ "aarch64-linux" ]; };

          hardware = {
            nvidia = {open = true; gsp.enable = true; modesetting.enable = true;package = config.boot.kernelPackages.nvidiaPackages.beta; };
            nvidia-container-toolkit.enable = true;
            graphics = {enable = true; enable32Bit= true;};
            enableAllFirmware = true;
            cpu.intel.updateMicrocode = true;};

          boot = {
            kernelPackages = pkgs.linuxPackages_latest;
            lanzaboote = { enable = true; autoEnrollKeys.enable = true;autoGenerateKeys.enable = true; pkiBundle = "/var/lib/sbctl"; };
            loader = { systemd-boot.configurationLimit = 5;systemd-boot.enable = lib.mkForce false; timeout = 0; };
            kernelModules = ["st" "sg" "vfio_pci" "vfio" "vfio_iommu_type1"] ;
            binfmt.emulatedSystems = [ "aarch64-linux" ];
            kernelParams = [ 
              "preempt=full" "8250.nr_uarts=0" "nvidia-drm.modeset=1" "mitigations=off" "clearcpuid=514" "clearcpuid=split_lock_detect"
              "rd.tpm2.wait-for-device=1" "tpm_tis.interrupts=0" "usbcore.autosuspend=-1" "split_lock_detect=off" "intel_pstate=disable"
              "zswap.compressor=zstd" "zswap.max_pool_percent=20" "zswap.enabled=1" "zswap.zpool=zsmalloc" "intel_iommu=on" "iommu=pt" "transparent_hugepage=madvise"
            ];
            kernel.sysctl = { "kernel.split_lock_mitigate" = 0; "vm.max_map_count" = 2147483642; "vm.swappiness" = 100; };
            initrd = {
              systemd.enable = true;
              kernelModules = [ "nvme" "xhci_pci" "usbhid" "tpm_tis" "tpm_crb" ];
              systemd.services.rollback = {
                description = "Rollback BTRFS root subvolume";
                wantedBy = [ "initrd.target" ]; after = [ "systemd-cryptsetup@enc.service" ]; before = [ "sysroot.mount" ];
                unitConfig.DefaultDependencies = "no"; serviceConfig.Type = "oneshot";
                script = ''
                  mkdir -p /mnt
                  mount -o subvol=/ /dev/mapper/enc /mnt
                  btrfs subvolume list -o /mnt/root | cut -f9 -d' ' | while read sub; do btrfs subvolume delete "/mnt/$sub"; done
                  btrfs subvolume delete /mnt/root
                  btrfs subvolume snapshot /mnt/root-blank /mnt/root
                  umount /mnt
                '';
              };
            };
          };
          systemd.settings.Manager ={DefaultTimeoutStopSec="2s";DefaultTimeoutStartSec="2s";};
          systemd.oomd.enable = false;
          systemd.tmpfiles.rules = [
          "d  /tmp/ch-conf   0700 nix users -"
          "L+ /home/nix/.config/chromium - nix users - /tmp/ch-conf"
        ];                
            fileSystems = {
            "/" = { fsType = "btrfs"; options = [ "subvol=root" "compress=zstd" ]; };
            "/nix" = { fsType = "btrfs"; options = [ "subvol=nix" "compress=zstd" ]; };
            "/persistent" = { fsType = "btrfs"; neededForBoot = true; options = [ "subvol=persistent" "compress=zstd" ]; };
          };

          environment.persistence."/persistent" = {
            hideMounts = true;
            directories = [ "/var/lib/"  "/var/log" ];
            files = [ "/etc/machine-id" ];
          };

          swapDevices = [{ device = "/swapfile"; size = 50000; priority = 10; }];

          networking = {
            hostName = "nixos"; 
            nameservers = [ "1.1.1.1" ];
            #useNetworkd = true;
            networkmanager.enable = true;
            firewall = { enable = true; trustedInterfaces = [ "tailscale0" ]; allowedUDPPorts = [ 41641 ]; logRefusedConnections = false;rejectPackets = false; };
          };

          security.pam.services = { login.u2fAuth = true; sudo.u2fAuth = true; };
          security.pam.u2f = { enable = true; control = "sufficient"; settings.cue = true; };
          security.rtkit.enable = true;

          services = {
          displayManager.cosmic-greeter.enable = true;
          desktopManager.cosmic.enable = true;
          sysprof.enable = true;
          xserver.videoDrivers = [ "nvidia" ];
          seatd.enable = true;
          tailscale.enable = true;
          flatpak.enable = true;
          pcscd.enable = true;
          flatpak.update.onActivation = true;
          fwupd.enable = true;
          tzupdate.enable = true;
          resolved.enable = true;
          udev.extraRules = ''ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]*", ATTR{queue/scheduler}="mq-deadline"'';
          scx = {
            enable = true;
            scheduler = "scx_bpfland";
          };
          pipewire = {
            enable = true;
            alsa.enable = true;
            alsa.support32Bit = true;
            pulse.enable = true;
            jack.enable = true;
            extraConfig.pipewire."92-low-latency" = {
              "context.properties" = {
                "default.clock.rate" = 48000;
                "default.clock.quantum" = 1024;
                "default.clock.min-quantum" = 32;
                "default.clock.max-quantum" = 2048;
              };
            };
          };
          snapper.configs = {
          persistent = {
            SUBVOLUME = "/persistent";
            TIMELINE_CREATE = true;
            TIMELINE_CLEANUP = true;
            INTERVAL = "hourly";
            ALLOW_USERS = [ "nix" ];
            TIMELINE_LIMIT_HOURLY = "24";
            TIMELINE_LIMIT_DAILY = "0";
            TIMELINE_LIMIT_WEEKLY = "0";
            TIMELINE_LIMIT_MONTHLY = "0";
            TIMELINE_LIMIT_YEARLY = "0";
          };
        };
        };

          xdg.portal = {enable = true;};
                      
          virtualisation = { containers.enable = true; podman = { enable = true; dockerCompat = true; defaultNetwork.settings.dns_enabled = true; }; };

          environment.systemPackages = with pkgs; [busybox toybox libcap jq  git-remote-gcrypt gnupg pinentry-curses chromium sbctl nvidia_oc];
          programs = {
            chromium = {enable = true;extraOpts = {"IncognitoModeAvailability" = 2;};};
            gnupg.agent = { enable = true;enableSSHSupport = true; pinentryPackage = pkgs.pinentry-curses;};
          };
          
          documentation.nixos.enable = false;
          systemd.services.nvidia-overclock = {
          description = "NVIDIA Overclocking Service";
          after = [ "network.target" "display-manager.service" ]; # Added display-manager to ensure drivers are loaded
          wantedBy = [ "multi-user.target" ];
  
         serviceConfig = {
         Type = "oneshot"; # Since it sets a value and exits, 'oneshot' is better than 'simple'
         ExecStart = "${pkgs.nvidia_oc}/bin/nvidia_oc set --index 0 --power-limit 300000 --freq-offset 400 --mem-offset 2800";
         User = "root";
         RemainAfterExit = true;
           };
         };
          users.mutableUsers = false;
          users.users.root.hashedPassword = "!";
          users.users.nix = {
            isNormalUser = true; shell = pkgs.nushell; description = "nix user"; extraGroups = [ "wheel" "tape" "video" "render" "seat" "audio" "input" ];
            hashedPassword = "$6$FA0MUKHblWK2Ym8O$aQx3otoJ2hYTDA2kyfhEdPFm5gJQgg/LUJ3GBOmr4/A2MtTwPUWd/ZlFlutCInhN7s7T/51fwWRGiJiM07R2r1";
          };

          home-manager.users.nix = { pkgs, ... }: {
            home.stateVersion = "26.05";
            manual = { manpages.enable = false; html.enable = false; json.enable = false; };
            home.packages = with pkgs; [ atuin btop carapace  fzf helix starship zellij zoxide foot nerd-fonts.jetbrains-mono ];
            home.persistence."/persistent" = {
              directories = [ 
                ".config" ".gnupg" ".local/share" ".steam" ".ssh"  ".var/app" "Documents" "Downloads" ];
              files = [  ];
            };
            fonts.fontconfig.enable = true;       
            programs = {
              git = { enable = true; settings.user = { name = "Leo Newton"; email = "leo253@pm.me"; }; settings.init.defaultBranch = "main"; };
              starship = { enable = true; enableNushellIntegration = true; };
              zoxide = { enable = true; enableNushellIntegration = true; };
              atuin = { enable = true; enableNushellIntegration = true; };
              foot = {enable = true; settings = {main ={font = "JetBrainsMono Nerd Font:size=13";};};};
              carapace = { enable = true; enableNushellIntegration = true; };
              fzf.enable = true; zellij.enable = true;
              nushell = {
                enable = true;
                configFile.text = ''
                  $env.config = { show_banner: false, edit_mode: vi }
                  def update [] { sudo nix flake update --flake ~/Documents/git/nixos/; sudo nixos-rebuild switch --flake ~/Documents/git/nixos/ }
                  def push [msg?: string] {
                    $env.GPG_TTY = (tty); gpg-connect-agent updatestartuptty /bye | ignore; git add -A
                    let m = if ($msg | is-empty) { (date now | format date '%Y-%m-%d %H:%M:%S') } else { $msg }; git commit -m $m; git push
                  }
                  $env.SSH_AUTH_SOCK = $"/run/user/(id -u)/gcr/ssh"; $env.GPG_TTY = (tty); gpg-connect-agent updatestartuptty /bye | ignore
                  def ubuntu [] { podman run --rm --gpus all -it -v $"($env.PWD):/data" -w /data ubuntu:latest bash }
                '';
                shellAliases = {};
              };
            };
          };
        })
      ];
    };
  };
}
