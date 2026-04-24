{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.prowlarr;
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  allTagNames = lib.unique (lib.concatMap (i: i.tags) cfg.config.indexers);
in
{
  mkJob = {
    name = "prowlarr-tags";
    description = "Ensure Prowlarr tags exist via API";
    after = [ "prowlarr-config.service" ];
    requires = [ "prowlarr-config.service" ];

    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

      echo "Fetching existing tags..."
      EXISTING_TAGS=$(${
        mkSecureCurl cfg.config.apiKey {
          url = "$BASE_URL/tag";
          extraArgs = "-S";
        }
      })

      ${concatMapStringsSep "\n" (tagName: ''
        if echo "$EXISTING_TAGS" | ${pkgs.jq}/bin/jq -e --arg label ${escapeShellArg tagName} '.[] | select(.label == $label)' >/dev/null 2>&1; then
          echo "Tag \"${tagName}\" already exists"
        else
          echo "Creating tag \"${tagName}\"..."
          CREATE_PAYLOAD=$(${pkgs.jq}/bin/jq -n --arg label ${escapeShellArg tagName} '{label: $label}')
          ${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/tag";
              method = "POST";
              headers = {
                "Content-Type" = "application/json";
              };
              data = "$CREATE_PAYLOAD";
              extraArgs = "-Sf";
            }
          } >/dev/null
          echo "Tag \"${tagName}\" created"
        fi
      '') allTagNames}

      echo "Prowlarr tags configuration complete"
    '';
  };
}
