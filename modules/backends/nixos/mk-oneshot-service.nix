{
  lib,
  pkgs,
}:
job: {
  inherit (job) description;
  after = job.after or [ ];
  before = job.before or [ ];
  requires = job.requires or [ ];
  requiredBy = job.requiredBy or [ ];
  wantedBy = job.wantedBy or [ "multi-user.target" ];
  path = job.path or [ ];
  environment = job.environment or { };

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  }
  // (job.serviceConfig or { });

  script = ''
    ${lib.optionalString ((job.stopUnits or [ ]) != [ ]) ''
      echo "Stopping dependent services..."
      ${lib.concatMapStringsSep "\n" (unit: "${pkgs.systemd}/bin/systemctl stop ${unit}") job.stopUnits}
    ''}
    ${job.script}
    ${lib.optionalString ((job.startUnits or [ ]) != [ ]) ''
      echo "Starting dependent services..."
      ${lib.concatMapStringsSep "\n" (unit: "${pkgs.systemd}/bin/systemctl start ${unit}") job.startUnits}
    ''}
    ${lib.optionalString ((job.restartUnits or [ ]) != [ ]) ''
      echo "Restarting dependent services..."
      ${lib.concatMapStringsSep "\n" (
        unit: "${pkgs.systemd}/bin/systemctl restart ${unit}"
      ) job.restartUnits}
    ''}
  '';
}
