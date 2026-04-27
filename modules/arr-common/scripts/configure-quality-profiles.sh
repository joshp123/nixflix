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

managed_names="$(jq -c '[.[] | select(.deleteUnmanaged != true) | .name]' "$profiles_json")"
delete_unmanaged="$(jq -r 'any(.[]; .deleteUnmanaged == true)' "$profiles_json")"

jq -c '.[]' "$profiles_json" | while IFS= read -r configured_profile; do
  delete_unmanaged_profile="$(printf '%s\n' "$configured_profile" | jq -r '.deleteUnmanaged // false')"
  if [ "$delete_unmanaged_profile" = "true" ]; then
    continue
  fi

  profile_name="$(printf '%s\n' "$configured_profile" | jq -r '.name')"
  if [ -z "$profile_name" ] || [ "$profile_name" = "null" ]; then
    echo "Configured quality profile is missing a name" >&2
    exit 1
  fi

  source_name="$(printf '%s\n' "$configured_profile" | jq -r '.sourceName // empty')"
  if [ -n "$source_name" ]; then
    source_profile="$(printf '%s\n' "$profiles" | jq -c --arg name "$source_name" 'first(.[] | select(.name == $name)) // empty')"
    if [ -z "$source_profile" ]; then
      echo "Source quality profile not found for ${profile_name}: ${source_name}" >&2
      exit 1
    fi
    configured_profile="$(
      jq -cn \
        --argjson source "$source_profile" \
        --argjson overrides "$configured_profile" \
        '$source * ($overrides | del(.sourceName, .deleteUnmanaged)) | .name = $overrides.name'
    )"
  fi

  disallowed_qualities="$(printf '%s\n' "$configured_profile" | jq -c '.disallowedQualities // []')"
  if [ "$disallowed_qualities" != "[]" ]; then
    configured_profile="$(
      printf '%s\n' "$configured_profile" | jq -c \
        --argjson disallowed "$disallowed_qualities" \
        '
          def rewrite:
            if type == "object" then
              (if (.quality.name? as $name | $name != null and ($disallowed | index($name))) then
                .allowed = false
              else
                .
              end)
              | with_entries(.value |= rewrite)
            elif type == "array" then
              map(rewrite)
            else
              .
            end;
          rewrite | del(.disallowedQualities)
        '
    )"
  fi

  existing_profile="$(printf '%s\n' "$profiles" | jq -c --arg name "$profile_name" 'first(.[] | select(.name == $name)) // empty')"

  if [ -n "$existing_profile" ]; then
    profile_id="$(printf '%s\n' "$existing_profile" | jq -r '.id')"
    payload="$(printf '%s\n' "$configured_profile" | jq -c --argjson id "$profile_id" '.id = $id')"
    echo "Updating quality profile: ${profile_name}"
    printf '%s\n' "$payload" | curl -fsS \
      -H "X-Api-Key: ${ARR_API_KEY}" \
      -H "Content-Type: application/json" \
      -X PUT \
      --data-binary @- \
      "${base_url}/qualityprofile/${profile_id}" >/dev/null
  else
    payload="$(printf '%s\n' "$configured_profile" | jq -c 'del(.id)')"
    echo "Creating quality profile: ${profile_name}"
    printf '%s\n' "$payload" | curl -fsS \
      -H "X-Api-Key: ${ARR_API_KEY}" \
      -H "Content-Type: application/json" \
      -X POST \
      --data-binary @- \
      "${base_url}/qualityprofile" >/dev/null
  fi
done

if [ "$delete_unmanaged" = "true" ]; then
  echo "Removing ${service_name} quality profiles not in configuration..."
  profiles="$(curl -fsS -H "X-Api-Key: ${ARR_API_KEY}" "${base_url}/qualityprofile")"
  replacement_profile_id="$(
    printf '%s\n' "$profiles" | jq -r --argjson managed "$managed_names" '
      first(.[] | select(.name as $name | $managed | index($name)) | .id) // empty
    '
  )"
  if [ -z "$replacement_profile_id" ]; then
    echo "No managed replacement quality profile found" >&2
    exit 1
  fi

  printf '%s\n' "$profiles" | jq -c '.[]' | while IFS= read -r existing_profile; do
    profile_name="$(printf '%s\n' "$existing_profile" | jq -r '.name')"
    profile_id="$(printf '%s\n' "$existing_profile" | jq -r '.id')"

    if printf '%s\n' "$managed_names" | jq -e --arg name "$profile_name" 'index($name)' >/dev/null; then
      continue
    fi

    echo "Deleting unmanaged quality profile: ${profile_name}"
    curl -fsS \
      -H "X-Api-Key: ${ARR_API_KEY}" \
      -X DELETE \
      "${base_url}/qualityprofile/${profile_id}?replaceWithId=${replacement_profile_id}" >/dev/null
  done
fi

echo "${service_name} quality profiles configuration complete"
