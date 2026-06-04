#!/usr/bin/env bash
set -euo pipefail

service_name="${1:?usage: configure-quality-profiles.sh SERVICE_NAME BASE_URL PROFILES_JSON}"
base_url="${2:?usage: configure-quality-profiles.sh SERVICE_NAME BASE_URL PROFILES_JSON}"
profiles_json="${3:?usage: configure-quality-profiles.sh SERVICE_NAME BASE_URL PROFILES_JSON}"

if [ -z "${ARR_API_KEY:-}" ]; then
  echo "ARR_API_KEY is required" >&2
  exit 1
fi

echo "Fetching ${service_name} quality profiles..."
profiles="$(curl -fsS -H "X-Api-Key: ${ARR_API_KEY}" "${base_url}/qualityprofile")"
payloads_file="$(mktemp)"
trap 'rm -f "$payloads_file"' EXIT

jq -c '.[]' "$profiles_json" | while IFS= read -r configured_profile; do
  profile_name="$(printf '%s\n' "$configured_profile" | jq -r '.name')"
  if [ -z "$profile_name" ] || [ "$profile_name" = "null" ]; then
    echo "Configured quality profile is missing a name" >&2
    exit 1
  fi

  source_name="$(printf '%s\n' "$configured_profile" | jq -r '.sourceName // empty')"
  existing_profile="$(printf '%s\n' "$profiles" | jq -c --arg name "$profile_name" 'first(.[] | select(.name == $name)) // empty')"
  if [ -n "$source_name" ]; then
    source_profile="$existing_profile"
    if [ -z "$source_profile" ]; then
      source_profile="$(printf '%s\n' "$profiles" | jq -c --arg name "$source_name" 'first(.[] | select(.name == $name)) // empty')"
    fi
    if [ -z "$source_profile" ]; then
      echo "Source quality profile not found for ${profile_name}: ${source_name}" >&2
      exit 1
    fi
    configured_profile="$(
      jq -cn \
        --argjson source "$source_profile" \
        --argjson overrides "$configured_profile" \
        '$source * ($overrides | del(.sourceName)) | .name = $overrides.name'
    )"
  fi

  allowed_qualities="$(printf '%s\n' "$configured_profile" | jq -c '.allowedQualities // []')"
  disallowed_qualities="$(printf '%s\n' "$configured_profile" | jq -c '.disallowedQualities // []')"
  if [ "$allowed_qualities" != "[]" ] || [ "$disallowed_qualities" != "[]" ]; then
    requested_qualities="$(jq -cn --argjson allowed "$allowed_qualities" --argjson disallowed "$disallowed_qualities" '$allowed + $disallowed | unique')"
    matched_qualities="$(
      printf '%s\n' "$configured_profile" | jq -c \
        --argjson requested "$requested_qualities" \
        '[.. | objects | (.quality.name? // .name? // empty) | select($requested | index(.))] | unique'
    )"
    missing_qualities="$(jq -cn --argjson requested "$requested_qualities" --argjson matched "$matched_qualities" '$requested - $matched')"
    if [ "$missing_qualities" != "[]" ]; then
      echo "Quality profile ${profile_name} is missing requested quality names: ${missing_qualities}" >&2
      exit 1
    fi

    configured_profile="$(
      printf '%s\n' "$configured_profile" | jq -c \
        --argjson allowed "$allowed_qualities" \
        --argjson disallowed "$disallowed_qualities" \
        '
          def rewrite:
            if type == "object" then
              (
                if ((.quality.name? // .name?) as $name | $name != null and ($allowed | index($name))) then
                  .allowed = true
                else
                  .
                end
              )
              | (
                if ((.quality.name? // .name?) as $name | $name != null and ($disallowed | index($name))) then
                  .allowed = false
                else
                  .
                end
              )
              | with_entries(.value |= rewrite)
            elif type == "array" then
              map(rewrite)
            else
              .
            end;
          rewrite | del(.allowedQualities, .disallowedQualities)
        '
    )"
  fi

  if [ -n "$existing_profile" ]; then
    profile_id="$(printf '%s\n' "$existing_profile" | jq -r '.id')"
    payload="$(printf '%s\n' "$configured_profile" | jq -c --argjson id "$profile_id" '.id = $id')"
    jq -cn \
      --arg action update \
      --arg name "$profile_name" \
      --arg url "${base_url}/qualityprofile/${profile_id}" \
      --argjson payload "$payload" \
      '{action: $action, name: $name, url: $url, payload: $payload}' >> "$payloads_file"
  else
    payload="$(printf '%s\n' "$configured_profile" | jq -c 'del(.id)')"
    jq -cn \
      --arg action create \
      --arg name "$profile_name" \
      --arg url "${base_url}/qualityprofile" \
      --argjson payload "$payload" \
      '{action: $action, name: $name, url: $url, payload: $payload}' >> "$payloads_file"
  fi
done

while IFS= read -r planned_profile; do
  action="$(printf '%s\n' "$planned_profile" | jq -r '.action')"
  profile_name="$(printf '%s\n' "$planned_profile" | jq -r '.name')"
  url="$(printf '%s\n' "$planned_profile" | jq -r '.url')"
  payload="$(printf '%s\n' "$planned_profile" | jq -c '.payload')"

  if [ "$action" = "update" ]; then
    echo "Updating quality profile: ${profile_name}"
    printf '%s\n' "$payload" | curl -fsS \
      -H "X-Api-Key: ${ARR_API_KEY}" \
      -H "Content-Type: application/json" \
      -X PUT \
      --data-binary @- \
      "$url" >/dev/null
  else
    echo "Creating quality profile: ${profile_name}"
    printf '%s\n' "$payload" | curl -fsS \
      -H "X-Api-Key: ${ARR_API_KEY}" \
      -H "Content-Type: application/json" \
      -X POST \
      --data-binary @- \
      "$url" >/dev/null
  fi
done < "$payloads_file"

echo "${service_name} quality profiles configuration complete"
