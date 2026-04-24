{
  pkgs,
}:
job:
let
  label = job.label or "org.nixflix.${job.name}";
  scriptPath = pkgs.writeShellScript job.name ''
    set -eu
    ${job.script}
  '';
  serviceConfig = {
    Label = label;
    ProgramArguments = [ "${scriptPath}" ];
    KeepAlive = false;
    RunAtLoad = true;
    WorkingDirectory = job.workingDirectory or "/";
    StandardOutPath = job.standardOutPath or "/tmp/${job.name}.stdout.log";
    StandardErrorPath = job.standardErrorPath or "/tmp/${job.name}.stderr.log";
    EnvironmentVariables = job.environment or { };
  }
  // (job.serviceConfig or { });
in
{
  inherit serviceConfig;
}
