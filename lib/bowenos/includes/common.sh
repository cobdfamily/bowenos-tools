#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-}"
NIX_FLAKE_FLAGS=(--extra-experimental-features "nix-command flakes")

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 2
  fi
}

nix_run() {
  require_command nix
  nix "${NIX_FLAKE_FLAGS[@]}" run "$@"
}

nix_eval_raw() {
  require_command nix
  nix "${NIX_FLAKE_FLAGS[@]}" eval --raw "$@"
}

validate_disk_mode() {
  local mode="$1"
  local source="${2:-inventory}"
  if [[ "${mode}" != "mirror" && "${mode}" != "single" ]]; then
    echo "Invalid disk mode '${mode}' in ${source}. Expected: mirror or single." >&2
    exit 2
  fi
}

validate_boot_mode() {
  local mode="$1"
  local source="${2:-inventory}"
  if [[ "${mode}" != "uefi" && "${mode}" != "bios" ]]; then
    echo "Invalid boot mode '${mode}' in ${source}. Expected: uefi or bios." >&2
    exit 2
  fi
}

COREUTILS_ROOT="$(nix_eval_raw --impure 'with import <nixpkgs> {}; pkgs.coreutils' 2>/dev/null || true)"
if [[ -n "${COREUTILS_ROOT}" ]]; then
  COREUTILS_BIN="${COREUTILS_ROOT}/bin"
  MKDIR="${COREUTILS_BIN}/mkdir"
  CP="${COREUTILS_BIN}/cp"
  RM="${COREUTILS_BIN}/rm"
  TEST="${COREUTILS_BIN}/test"
else
  MKDIR="mkdir"
  CP="cp"
  RM="rm"
  TEST="test"
fi

set_local_nix_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  if [[ ! -f "${file}" ]]; then
    echo "Missing file: ${file}" >&2
    exit 2
  fi
  tmp="$(mktemp)"

  awk -v k="${key}" -v v="${value}" '
    BEGIN { found = 0; }
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      print "  " k " = " v ";"
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        # Insert before last } if present, otherwise append.
        if (NR > 0) {
          # handled by second pass
        }
      }
    }
  ' "${file}" > "${tmp}"

  if ! grep -q "^[[:space:]]*${key}[[:space:]]*=" "${tmp}"; then
    awk -v k="${key}" -v v="${value}" '
      BEGIN { inserted = 0; }
      /}[[:space:]]*$/ && !inserted {
        print "  " k " = " v ";"
        inserted = 1
      }
      { print }
      END {
        if (!inserted) {
          print "  " k " = " v ";"
        }
      }
    ' "${tmp}" > "${tmp}.2"
    mv "${tmp}.2" "${tmp}"
  fi

  mv "${tmp}" "${file}"
}

select_disk_by_id() {
  local prompt="$1"
  local -n _choices=$2
  local -n _selected=$3

  while true; do
    echo "${prompt}"
    local i=1
    for d in "${_choices[@]}"; do
      echo "  ${i}) ${d}"
      i=$((i + 1))
    done
    read -r -p "Select disk number: " idx
    if [[ "${idx}" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#_choices[@]} )); then
      local choice="${_choices[$((idx-1))]}"
      # ensure not already selected
      for s in "${_selected[@]}"; do
        if [[ "${s}" == "${choice}" ]]; then
          echo "Disk already selected. Choose a different disk."
          choice=""
          break
        fi
      done
      if [[ -n "${choice}" ]]; then
        _selected+=("${choice}")
        break
      fi
    else
      echo "Invalid selection."
    fi
  done
}

select_host_from_inventory() {
  local inventory_root="${1:-/tmp/bowenos}"
  local hosts_dir="${inventory_root}/hosts"

  if [[ -n "${HOST}" ]]; then
    return 0
  fi

  if [[ ! -d "${hosts_dir}" ]]; then
    echo "HOST is not set and ${hosts_dir} does not exist." >&2
    exit 2
  fi

  mapfile -t _hosts < <(find "${hosts_dir}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)
  if [[ ${#_hosts[@]} -eq 0 ]]; then
    echo "No hosts found under ${hosts_dir}." >&2
    exit 2
  fi

  if [[ ${#_hosts[@]} -eq 1 ]]; then
    HOST="${_hosts[0]}"
    return 0
  fi

  echo "HOST is not set. Select a host:"
  local i=1
  for h in "${_hosts[@]}"; do
    echo "  ${i}) ${h}"
    i=$((i + 1))
  done
  read -r -p "Select host number: " idx
  if [[ "${idx}" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#_hosts[@]} )); then
    HOST="${_hosts[$((idx-1))]}"
  else
    echo "Invalid selection." >&2
    exit 2
  fi
}

validate_target() {
  local target="$1"
  local host="${2:-${HOST:-unknown}}"
  local source_path="${3:-hosts/${host}/local.nix}"

  case "${target}" in
    compute|computeplusstorage|storage) ;;
    *)
      echo "Invalid target '${target}' in ${source_path}. Expected one of: compute, computeplusstorage, storage." >&2
      exit 2
      ;;
  esac
}

load_target_from_inventory() {
  local inventory_root="${1:-/tmp/bowenos}"
  local host="${2:-${HOST:-}}"

  if [[ -z "${host}" ]]; then
    echo "HOST is required to load target from inventory." >&2
    exit 2
  fi

  TARGET="$(nix_eval_raw "path:${inventory_root}#hostInfo.${host}.target")"
  validate_target "${TARGET}" "${host}" "hosts/${host}/local.nix"
}

ensure_mountpoint() {
  local path="$1"
  local label="$2"
  require_command mount
  require_command mountpoint

  if mountpoint -q "${path}"; then
    return 0
  fi

  ${MKDIR} -p "${path}"
  if [[ -z "${label}" ]]; then
    echo "Required mountpoint is not mounted: ${path}" >&2
    exit 2
  fi

  if [[ ! -e "/dev/disk/by-partlabel/${label}" ]]; then
    echo "Required mountpoint is not mounted: ${path}" >&2
    echo "Missing partition label: /dev/disk/by-partlabel/${label}" >&2
    exit 2
  fi

  if ! mount "/dev/disk/by-partlabel/${label}" "${path}"; then
    echo "Failed to mount /dev/disk/by-partlabel/${label} on ${path}" >&2
    exit 2
  fi

  if ! mountpoint -q "${path}"; then
    echo "Required mountpoint is not mounted: ${path}" >&2
    exit 2
  fi
}
