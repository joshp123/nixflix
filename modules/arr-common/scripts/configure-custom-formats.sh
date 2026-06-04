#!/usr/bin/env bash
set -euo pipefail

service_name="${1:?usage: configure-custom-formats.sh SERVICE_NAME BASE_URL CUSTOM_FORMATS_JSON}"
base_url="${2:?usage: configure-custom-formats.sh SERVICE_NAME BASE_URL CUSTOM_FORMATS_JSON}"
formats_json="${3:?usage: configure-custom-formats.sh SERVICE_NAME BASE_URL CUSTOM_FORMATS_JSON}"

if [ -z "${ARR_API_KEY:-}" ]; then
  echo "ARR_API_KEY is required" >&2
  exit 1
fi

echo "Fetching ${service_name} custom formats..."
custom_formats="$(curl -fsS -H "X-Api-Key: ${ARR_API_KEY}" "${base_url}/customformat")"
quality_profiles="$(curl -fsS -H "X-Api-Key: ${ARR_API_KEY}" "${base_url}/qualityprofile")"

jq -c '.[]' "$formats_json" | while IFS= read -r configured_format; do
  format_name="$(printf '%s\n' "$configured_format" | jq -r '.name')"
  if [ -z "$format_name" ] || [ "$format_name" = "null" ]; then
    echo "Configured custom format is missing a name" >&2
    exit 1
  fi

  existing_format="$(printf '%s\n' "$custom_formats" | jq -c --arg name "$format_name" 'first(.[] | select(.name == $name)) // empty')"
  payload="$(printf '%s\n' "$configured_format" | jq -c 'del(.scores, .id) | .includeCustomFormatWhenRenaming //= false')"

  if [ -n "$existing_format" ]; then
    format_id="$(printf '%s\n' "$existing_format" | jq -r '.id')"
    payload="$(printf '%s\n' "$payload" | jq -c --argjson id "$format_id" '.id = $id')"
    echo "Updating custom format: ${format_name}"
    updated_format="$(
      printf '%s\n' "$payload" | curl -fsS \
        -H "X-Api-Key: ${ARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -X PUT \
        --data-binary @- \
        "${base_url}/customformat/${format_id}"
    )"
  else
    echo "Creating custom format: ${format_name}"
    updated_format="$(
      printf '%s\n' "$payload" | curl -fsS \
        -H "X-Api-Key: ${ARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -X POST \
        --data-binary @- \
        "${base_url}/customformat"
    )"
    format_id="$(printf '%s\n' "$updated_format" | jq -r '.id')"
  fi

  custom_formats="$(printf '%s\n' "$custom_formats" | jq -c --argjson updated "$updated_format" 'map(if .id == $updated.id then $updated else . end) + (if any(.[]; .id == $updated.id) then [] else [$updated] end)')"

  printf '%s\n' "$configured_format" | jq -r '(.scores // {}) | to_entries[] | @base64' | while IFS= read -r encoded_score; do
    score_entry="$(printf '%s' "$encoded_score" | base64 --decode)"
    profile_name="$(printf '%s\n' "$score_entry" | jq -r '.key')"
    score="$(printf '%s\n' "$score_entry" | jq -r '.value')"
    quality_profiles="$(curl -fsS -H "X-Api-Key: ${ARR_API_KEY}" "${base_url}/qualityprofile")"
    profile="$(printf '%s\n' "$quality_profiles" | jq -c --arg name "$profile_name" 'first(.[] | select(.name == $name)) // empty')"

    if [ -z "$profile" ]; then
      echo "Quality profile not found for custom format ${format_name}: ${profile_name}" >&2
      exit 1
    fi

    profile_id="$(printf '%s\n' "$profile" | jq -r '.id')"
    updated_profile="$(
      printf '%s\n' "$profile" | jq -c \
        --argjson format "$format_id" \
        --arg name "$format_name" \
        --argjson score "$score" \
        '
          .formatItems = (
            ((.formatItems // []) | map(select(.format != $format and .name != $name)))
            + [{format: $format, name: $name, score: $score}]
          )
        '
    )"

    echo "Assigning custom format ${format_name} to ${profile_name}: ${score}"
    printf '%s\n' "$updated_profile" | curl -fsS \
      -H "X-Api-Key: ${ARR_API_KEY}" \
      -H "Content-Type: application/json" \
      -X PUT \
      --data-binary @- \
      "${base_url}/qualityprofile/${profile_id}" >/dev/null
  done
done

echo "${service_name} custom formats configuration complete"
