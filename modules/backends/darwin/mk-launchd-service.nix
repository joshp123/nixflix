_: job:
let
  label = job.label or "org.nixflix.${job.name}";
  serviceConfig = {
    Label = label;
    KeepAlive = true;
    RunAtLoad = true;
  }
  // (job.serviceConfig or { });
in
{
  inherit serviceConfig;
}
