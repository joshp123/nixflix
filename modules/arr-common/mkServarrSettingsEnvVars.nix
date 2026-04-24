{ lib }:
name: settings:
with lib;
pipe settings [
  (mapAttrsRecursive (
    path: value:
    optionalAttrs (value != null) {
      name = toUpper "${name}__${concatStringsSep "__" path}";
      value = toString (if isBool value then boolToString value else value);
    }
  ))
  (collect (x: isString x.name or false && isString x.value or false))
  listToAttrs
]
