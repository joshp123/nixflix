{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = nixflix.seerr;
  authUtil = import ./authUtil.nix {
    inherit
      lib
      pkgs
      cfg
      ;
  };
  baseUrl = "http://127.0.0.1:${toString cfg.port}";
  discoverSliderTypeIds = {
    RECENTLY_ADDED = 1;
    RECENT_REQUESTS = 2;
    PLEX_WATCHLIST = 3;
    TRENDING = 4;
    POPULAR_MOVIES = 5;
    MOVIE_GENRES = 6;
    UPCOMING_MOVIES = 7;
    STUDIOS = 8;
    POPULAR_TV = 9;
    TV_GENRES = 10;
    UPCOMING_TV = 11;
    NETWORKS = 12;
  };
  enabledTypesFile = pkgs.writeText "seerr-discover-enabled-types.json" (
    builtins.toJSON (
      map (type: discoverSliderTypeIds.${type}) cfg.settings.discover.enabledBuiltInSliderTypes
    )
  );
in
{
  config =
    mkIf (nixflix.enable && cfg.enable && cfg.settings.discover.enabledBuiltInSliderTypes != null)
      {
        systemd.services.seerr-discover = {
          description = "Configure Seerr discover sliders";
          after = [ "seerr-user-settings.service" ];
          requires = [ "seerr-user-settings.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          script = ''
            set -euo pipefail

            BASE_URL="${baseUrl}"
            source ${authUtil.authScript}

            sliders="$(${pkgs.curl}/bin/curl -fsS \
              --max-time 30 \
              ${authUtil.curlAuthArgs} \
              "$BASE_URL/api/v1/settings/discover")"

            payload="$(echo "$sliders" | ${pkgs.jq}/bin/jq --slurpfile enabledTypes "${enabledTypesFile}" \
              'map(.enabled = (.type as $type | $enabledTypes[0] | index($type) != null))')"

            response="$(${pkgs.curl}/bin/curl -sS -X POST \
              --max-time 30 \
              ${authUtil.curlAuthArgs} \
              -H "Content-Type: application/json" \
              -d "$payload" \
              -w "\n%{http_code}" \
              "$BASE_URL/api/v1/settings/discover")"

            http_code="$(echo "$response" | ${pkgs.coreutils}/bin/tail -n1)"
            if [ "$http_code" != "200" ] && [ "$http_code" != "201" ] && [ "$http_code" != "204" ]; then
              echo "Failed to configure Seerr discover sliders (HTTP $http_code)" >&2
              echo "$response" | ${pkgs.gnused}/bin/sed '$d' >&2
              exit 1
            fi

            echo "Seerr discover sliders configured"
          '';
        };
      };
}
