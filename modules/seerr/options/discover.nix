{ lib, ... }:
with lib;
{
  options.nixflix.seerr.settings.discover = {
    enabledBuiltInSliderTypes = mkOption {
      type = types.nullOr (types.listOf (
        types.enum [
          "RECENTLY_ADDED"
          "RECENT_REQUESTS"
          "PLEX_WATCHLIST"
          "TRENDING"
          "POPULAR_MOVIES"
          "MOVIE_GENRES"
          "UPCOMING_MOVIES"
          "STUDIOS"
          "POPULAR_TV"
          "TV_GENRES"
          "UPCOMING_TV"
          "NETWORKS"
        ]
      ));
      default = null;
      example = [ "RECENTLY_ADDED" ];
      description = ''
        Seerr built-in discover slider types to keep enabled. Null preserves Seerr's defaults.
      '';
    };
  };
}
