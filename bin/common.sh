#!/bin/bash

steptxt="----->"
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'                              # No Color
CURL="curl -L --retry 15 --retry-delay 2" # retry for up to 30 seconds

info() {
  echo -e "${GREEN}       $*${NC}"
}

warn() {
  echo -e "${YELLOW} !!    $*${NC}"
}

err() {
  echo -e "${RED} !!    $*${NC}" >&2
}

step() {
  echo "$steptxt $*"
}

start() {
  echo -n "$steptxt $*... "
}

finished() {
  echo "done"
}

function indent() {
  c='s/^/       /'
  case $(uname) in
  Darwin) sed -l "$c" ;; # mac/bsd sed: -l buffers on line boundaries
  *) sed -u "$c" ;;      # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
  esac
}

function read_version_github_json() {
  local json_file="$1"
  local latest_release_version
  latest_release_version=""
  latest_release_version=$(< "${json_file}" jq '.tag_name' | xargs)
  latest_release_version="${latest_release_version%\"}"
  latest_release_version="${latest_release_version#\"}"
  # remove first character: 'v'
  latest_release_version="${latest_release_version:1}"
  echo "$latest_release_version"
}

function fetch_github_latest_release() {
  local location="$1"
  local repo="$2"
  local repo_checksum
  repo_checksum=$(printf "%s" "${repo}" | sha256sum | grep -o '^\S\+')
  local http_code
  if [[ -f "$ENV_DIR/GITHUB_ID" ]]; then
    GITHUB_ID=$(cat "$ENV_DIR/GITHUB_ID")
  fi
  if [[ -f "$ENV_DIR/GITHUB_SECRET" ]]; then
    GITHUB_SECRET=$(cat "$ENV_DIR/GITHUB_SECRET")
  fi
  local latest_release_url
  latest_release_url="https://api.github.com/repos/${repo}/releases/latest"
  http_code=$(curl -L --retry 15 --retry-delay 2 -G -o "${TMP_PATH}/latest_release_${repo_checksum}.json" -w '%{http_code}' -u "${GITHUB_ID}:${GITHUB_SECRET}" -H "Accept: application/vnd.github.v3+json" "${latest_release_url}")
  local latest_release_version
  latest_release_version=""
  if [[ $http_code == 200 ]]; then
    latest_release_version=$(read_version_github_json "${TMP_PATH}/latest_release_${repo_checksum}.json")
  fi
  echo "$latest_release_version"
}

function fetch_krakend_dist() {
  local version="$1"
  local location="$2"
  local dist="krakend_${version}_amd64_generic-linux.tar.gz"
  local dist_url
  local download_url
  local tag_name
  tag_name="v${version}"
  download_url="https://github.com/krakend/krakend-ce/releases/download/${tag_name}"
  dist_url=$(echo "${download_url}/${dist}" | xargs)
  dist_url="${dist_url%\"}"
  dist_url="${dist_url#\"}"
  local sha1_dist
  sha1_dist=checksums.txt
  local sha1_url
  sha1_url=$(echo "${download_url}/${sha1_dist}" | xargs)
  sha1_url="${sha1_url%\"}"
  sha1_url="${sha1_url#\"}"
  step "Fetch krakend ${version} dist"
  if [ -f "${CACHE_DIR}/dist/${dist}" ]; then
    info "File is already downloaded"
  else
    ${CURL} -g -o "${CACHE_DIR}/dist/${dist}" "${dist_url}"
  fi
  ${CURL} -g -o "${CACHE_DIR}/dist/${sha1_dist}" "${sha1_url}"
  local file_checksum
  # https://www.krakend.io/docs/overview/verifying-packages/
  cd "${CACHE_DIR}/dist/" || exit
  file_checksum="$(shasum --check --ignore-missing "${sha1_dist}" | cut -d : -f 2)"
  local checksum
  checksum=" OK"
  if [ "$checksum" != "$file_checksum" ]; then
    err "Krakend checksum file downloaded not valid"
    exit 1
  else
    info "Krakend checksum valid"
  fi
  mkdir -p "${location}/krakend-${version}"
  tar xzf "${dist}" -C "$location/krakend-${version}"
  mv "$location/krakend-${version}/etc/krakend" "$location/krakend-${version}/config"
  mv "$location/krakend-${version}/usr/bin" "$location/krakend-${version}/bin"
  rm -rf "$location/krakend-${version}/etc"
  rm -rf "$location/krakend-${version}/usr"
  finished
}