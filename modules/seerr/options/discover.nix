{ lib, ... }:
with lib;
{
  options.nixflix.seerr.settings.discover = {
    enableBuiltInSliders = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Seerr's built-in discover sliders on the home page.";
    };
  };
}
