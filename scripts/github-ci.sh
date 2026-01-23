#!/usr/bin/env bash
set -euo pipefail

token=${GITHUB_TOKEN:-}
repo_full=${GITHUB_REPOSITORY:-${REPO_FULL:-}}

if [[ -z "$token" ]]; then
  echo "GITHUB_TOKEN is required" >&2
  exit 1
fi

if [[ -z "$repo_full" ]]; then
  echo "GITHUB_REPOSITORY or REPO_FULL is required" >&2
  exit 1
fi

if [[ "$repo_full" != */* ]]; then
  echo "Invalid GITHUB_REPOSITORY: $repo_full" >&2
  exit 1
fi

base_branch=${BASE_BRANCH:-main}
branch_prefix=${AUTOMATION_BRANCH_PREFIX:-auto}
label=${AUTOMATION_LABEL:-automation}
heartbeat_path=${AUTOMATION_FILE_PATH:-automation/heartbeat.txt}
close_ratio=${CLOSE_RATIO:-0.2}
merge_ratio=${MERGE_RATIO:-0.2}
update_ratio=${UPDATE_RATIO:-0.2}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command git
require_command gh
require_command jq

ensure_git_repository() {
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Git repository not found. Run the automation inside a cloned repo (mount it into the container and set the working directory accordingly)." >&2
    exit 1
  fi
}

ensure_git_identity() {
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
}

append_heartbeat() {
  local branch_name="$1"
  mkdir -p "$(dirname "$heartbeat_path")"
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$branch_name" >> "$heartbeat_path"
}

random_int() {
  local min="$1"
  local max="$2"
  echo $((RANDOM % (max - min + 1) + min))
}

ratio_count() {
  local total="$1"
  local ratio="$2"
  awk -v total="$total" -v ratio="$ratio" 'BEGIN {
    if (ratio + 0 != ratio || ratio <= 0) { print 0; exit }
    count = int(total * ratio);
    if (count < 0) { count = 0 }
    print count
  }'
}

list_automation_pulls() {
  gh pr list \
    --repo "$repo_full" \
    --state open \
    --json number,headRefName,labels \
    | jq -c --arg prefix "${branch_prefix}/" --arg label "$label" \
      '.[] | select(.headRefName | startswith($prefix) or (.labels[]?.name == $label))'
}

create_pull_requests() {
  local count="$1"
  if (( count <= 0 )); then
    return
  fi

  local run_stamp
  run_stamp=$(date -u +"%Y-%m-%dT%H-%M-%SZ")

  for ((i=1; i<=count; i++)); do
    local branch_name
    branch_name="${branch_prefix}/${run_stamp}-${i}"
    git checkout "$base_branch"
    git pull --ff-only origin "$base_branch"
    git checkout -b "$branch_name"
    append_heartbeat "$branch_name"
    git add "$heartbeat_path"
    git commit -m "chore: heartbeat $branch_name"
    git push -u origin "$branch_name"

    gh pr create \
      --repo "$repo_full" \
      --base "$base_branch" \
      --head "$branch_name" \
      --title "Automation: $branch_name" \
      --body "Automated PR generated on schedule." \
      --label "$label" \
      >/dev/null
  done
}

close_pull_requests() {
  local pr_lines=($@)
  for pr_line in "${pr_lines[@]}"; do
    local number
    number=$(jq -r '.number' <<<"$pr_line")
    gh pr close "$number" --repo "$repo_full"
  done
}

update_pull_branches() {
  local pr_lines=($@)
  for pr_line in "${pr_lines[@]}"; do
    local branch_name
    branch_name=$(jq -r '.headRefName' <<<"$pr_line")
    git fetch origin "$branch_name"
    git checkout "$branch_name"
    git pull --ff-only origin "$branch_name"
    append_heartbeat "$branch_name"
    git add "$heartbeat_path"
    git commit -m "chore: update $branch_name"
    git push origin "$branch_name"
  done
}

rebase_and_merge_pulls() {
  local pr_lines=($@)
  for pr_line in "${pr_lines[@]}"; do
    local number
    number=$(jq -r '.number' <<<"$pr_line")
    if ! gh pr update-branch "$number" --repo "$repo_full"; then
      echo "Update branch failed for PR #$number" >&2
    fi
    if ! gh pr merge "$number" --repo "$repo_full" --squash; then
      echo "Merge failed for PR #$number" >&2
    fi
  done
}

main() {
  local repo_dir
  repo_dir=${REPO_DIR:-$(basename "$repo_full")}
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    git clone "https://github.com/$repo_full.git" "$repo_dir"
    cd "$repo_dir"
  fi

  ensure_git_repository
  ensure_git_identity
  git fetch origin --prune

  local create_count
  create_count=$(random_int 1 3)
  create_pull_requests "$create_count"

  mapfile -t open_pulls < <(list_automation_pulls || true)
  local open_count=${#open_pulls[@]}

  local close_count
  close_count=$(ratio_count "$open_count" "$close_ratio")
  local update_count
  update_count=$(ratio_count "$open_count" "$update_ratio")

  local merge_count
  merge_count=$(ratio_count "$open_count" "$merge_ratio")

  local close_targets=()
  if (( close_count > 0 )); then
    mapfile -t close_targets < <(printf '%s\n' "${open_pulls[@]}" | shuf -n "$close_count")
    close_pull_requests "${close_targets[@]}"
  fi

  declare -A closed_set=()
  for pr_line in "${close_targets[@]}"; do
    local number
    number=$(jq -r '.number' <<<"$pr_line")
    closed_set["$number"]=1
  done

  local remaining_after_close=()
  for pr_line in "${open_pulls[@]}"; do
    local number
    number=$(jq -r '.number' <<<"$pr_line")
    if [[ -z "${closed_set[$number]+x}" ]]; then
      remaining_after_close+=("$pr_line")
    fi
  done

  if (( ${#remaining_after_close[@]} > 0 )); then
    local update_targets=()
    if (( update_count > 0 )); then
      mapfile -t update_targets < <(printf '%s\n' "${remaining_after_close[@]}" | shuf -n "$update_count")
      update_pull_branches "${update_targets[@]}"
    fi

    declare -A updated_set=()
    for pr_line in "${update_targets[@]}"; do
      local number
      number=$(jq -r '.number' <<<"$pr_line")
      updated_set["$number"]=1
    done

    local remaining_after_update=()
    for pr_line in "${remaining_after_close[@]}"; do
      local number
      number=$(jq -r '.number' <<<"$pr_line")
      if [[ -z "${updated_set[$number]+x}" ]]; then
        remaining_after_update+=("$pr_line")
      fi
    done

    if (( ${#remaining_after_update[@]} > 0 )); then
      local merge_targets=()
      if (( merge_count > 0 )); then
        mapfile -t merge_targets < <(printf '%s\n' "${remaining_after_update[@]}" | shuf -n "$merge_count")
        rebase_and_merge_pulls "${merge_targets[@]}"
      fi
    fi
  fi

  git checkout "$base_branch"
}

main "$@"
