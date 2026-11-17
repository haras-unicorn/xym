let
  user = "xym";

  # the installer writes the password hash of the user here
  passwordPath = "/etc/xym/password";
in
{
  self.lib.access.user = user;

  self.lib.inject.password = passwordPath;

  self.nixosModules.access = {
    self = false;
    flake = true;

    value = {
      users.users.${user} = {
        isNormalUser = true;
        # wheel is for sudo, and it reads the journal too
        extraGroups = [ "wheel" ];
        hashedPasswordFile = passwordPath;
      };

      security.sudo.enable = true;

      services.openssh = {
        enable = true;
        openFirewall = true;
        settings = {
          PermitRootLogin = "no";
          PasswordAuthentication = true;
          KbdInteractiveAuthentication = false;
          AllowUsers = [ user ];
        };
      };
    };
  };
}
