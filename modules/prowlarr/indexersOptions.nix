{ lib, ... }:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
in
{
  options.nixflix.prowlarr.config.indexers = mkOption {
    type = types.listOf (
      types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the Prowlarr indexer schema.";
          };
          apiKey = secrets.mkSecretOption {
            description = "API key for the indexer.";
            nullable = true;
          };
          username = secrets.mkSecretOption {
            description = "Username for the indexer.";
            nullable = true;
          };
          password = secrets.mkSecretOption {
            description = "Password for the indexer.";
            nullable = true;
          };
          appProfileId = mkOption {
            type = types.int;
            default = 1;
            description = "Application profile ID for the indexer.";
          };
          tags = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Prowlarr tag labels to attach to this indexer.";
          };
        };
      }
    );
    default = [ ];
    description = ''
      List of indexers to configure in Prowlarr.

      Any additional attributes beyond name, apiKey, username, password, and appProfileId
      are applied as field values to the matching Prowlarr indexer schema.
    '';
  };
}
