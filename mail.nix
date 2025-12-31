{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      (builtins.fetchTarball {
      # Pick a release version you are interested in and set its hash, e.g.
      url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/nixos-25.11/nixos-mailserver-nixos-25.11.tar.gz";
      # To get the sha256 of the nixos-mailserver tarball, we can use the nix-prefetch-url command:
      # release="nixos-25.11"; nix-prefetch-url "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/${release}/nixos-mailserver-${release}.tar.gz" --unpack
      sha256 = "0pqc7bay9v360x2b7irqaz4ly63gp4z859cgg5c04imknv0pwjqw";
    })
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree         = true;

  ####################
  # Boot & Kernel    #
  ####################
  boot.loader.systemd-boot.enable             = true;
  boot.loader.efi.canTouchEfiVariables        = true;
  boot.loader.timeout                         = 0;
  
  # FIXED: Changed from limine.maxGenerations to the correct systemd-boot option
  boot.loader.systemd-boot.configurationLimit = 5; 

  boot.kernelParams = [ "quiet" ];

  boot.initrd = {
    systemd.enable   = true;
    kernelModules    = [ ];
  };
  systemd.settings.Manager = { DefaultTimeoutStopSec = "5s"; };

  ############
  # Network  #
  ############
  networking = {
    networkmanager.enable = true;
    firewall.enable       = true;
    hostName              = "nixos";
  };

  ########################
  # PostgresSQL          #
  ########################
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    #settings.port = 2053;
    
    # Allow network connections (listen on all interfaces)
    enableTCPIP = true;
    
    # Configure authentication
    # 1. Local users (socket) can log in without password (peer/trust)
    # 2. Network users (host) must use a password (scram-sha-256)
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
      host  all       all     127.0.0.1/32   trust
      host  all       all     ::1/128        trust
      host  all       all     0.0.0.0/0      scram-sha-256
    '';
        # Optional: Auto-create a database and user
    ensureDatabases = [ "mydb" ];
    ensureUsers = [
      {
        name = "mydb";
        ensureDBOwnership = true;
      }
    ];
  };
  ##TOR
  services.tor = {
  enable = true;
  openFirewall = true;
  relay = {
    enable = true;
    role = "relay";
  };
  settings = {
    ContactInfo = "toradmin@example.org";
    Nickname = "toradmin";
    ORPort = 9001;
    ControlPort = 9051;
    BandWidthRate = "1 MBytes";
  };
};
  
  ########################
  # Programs & Services  #
  ########################
  services.automatic-timezoned.enable = true;
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  
  programs = {
    fish = { enable = true; };
    mosh = { enable = true; };
    tmux = { enable = true; };
  };
  environment.systemPackages = [
    pkgs.dua
    pkgs.btop
    pkgs.helix
    pkgs.vim
    pkgs.acme-sh
  ];

  ###############
  # Users       #
  ###############
  users.users.nix = {
    isNormalUser = true;
    description  = "nix user";
    extraGroups  = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII4u+rF4q8yKM7Ect+BNcJQw3QMol4S555DzPQRLTOWq leo@Mac.lan"
    ];
  };

  #################
  # Security      #
  #################
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable          = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.qemuGuest.enable = true;
  #networking.firewall.allowedTCPPorts = [ 2053 ];
  mailserver = {
    enable = true;
    stateVersion = 3;
    virusScanning = false;
    fullTextSearch = {
      memoryLimit = 2000;
      enable = true;
      # index new email as they arrive
      autoIndex = true;
      enforced = "body";
    };
    fqdn = "mail.freecodersguild.org";
    domains = [ "freecodersguild.org" ];

    # A list of all login accounts. To create the password hashes, use
    # nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'
    loginAccounts = {
      "leo@freecodersguild.org" = {
        catchAll = ["freecodersguild.org"];
        hashedPasswordFile = "/etc/mailpass";
        aliases = ["postmaster@freecodersguild.org"];
      };
      #"user2@example.com" = { ... };
    };

    # Use Let's Encrypt certificates. Note that this needs to set up a stripped
    # down nginx and opens port 80.
    certificateScheme = "acme-nginx";
  };
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "security@freecodersguild.org";

  services.rspamd.extraConfig = ''
    actions {
      # Set thresholds insanely high so nothing is ever rejected or flagged
      reject = 5000;
      add_header = 5000;
      greylist = 5000; 
    }
  '';

  ########################
  # System State Version #
  ########################
  system.stateVersion = "25.11";
}
