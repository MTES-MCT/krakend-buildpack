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

function install_jq() {
  if [[ -f "${ENV_DIR}/JQ_VERSION" ]]; then
    JQ_VERSION=$(cat "${ENV_DIR}/JQ_VERSION")
  else
    JQ_VERSION=1.7.1
  fi
  step "Fetching jq $JQ_VERSION"
  if [ -f "${CACHE_DIR}/dist/jq-$JQ_VERSION" ]; then
    info "File already downloaded"
  else
    ${CURL} -o "${CACHE_DIR}/dist/jq-$JQ_VERSION" "https://github.com/stedolan/jq/releases/download/jq-$JQ_VERSION/jq-linux64"
  fi
  cp "${CACHE_DIR}/dist/jq-$JQ_VERSION" "${BUILD_DIR}/bin/jq"
  chmod +x "${BUILD_DIR}/bin/jq"
  finished
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
    latest_release_version=$(< "${TMP_PATH}/latest_release_${repo_checksum}.json" jq '.tag_name' | xargs)
    latest_release_version="${latest_release_version%\"}"
    latest_release_version="${latest_release_version#\"}"
  fi
  echo "$latest_release_version"
}

function read_version_github_json() {
  local json_file="$1"
  local latest_release_version
  latest_release_version=""
  latest_release_version=$(< "${json_file}" jq '.tag_name' | xargs)
  latest_release_version="${latest_release_version%\"}"
  latest_release_version="${latest_release_version#\"}"

  echo "$latest_release_version"
}

function fetch_krakend_dist() {
  local version="$1"
  local location="$2"
  local dist="krakend_${version}_amd64_generic-linux.tar.gz"
  local dist_url
  local download_url
  local major_version
  major_version="${version%.*}"
  major_version="${major_version%.*}"
  download_url="https://github.com/krakend/krakend-ce/releases/download/${version}"
  dist_url=$(echo "${download_url}/${dist}" | xargs)
  dist_url="${dist_url%\"}"
  dist_url="${dist_url#\"}"
  local sha1_dist
  sha1_dist=$(echo "${dist}.asc" | xargs)
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
  ${CURL} -g -o "${CACHE_DIR}/dist/${dist}.asc" "${sha1_url}"
  local file_checksum
  # https://www.krakend.io/docs/overview/verifying-packages/
  file_checksum="$(shasum "${CACHE_DIR}/dist/${dist}" | cut -d \  -f 1)"
  local checksum
  checksum=$(cat "${CACHE_DIR}/dist/${dist}.asc")
  if [ "$checksum" != "$file_checksum" ]; then
    err "Kralend checksum file downloaded not valid"
    exit 1
  else
    info "Kralend checksum valid"
  fi
  tar xzf "$CACHE_DIR/dist/${dist}" -C "$location"
  finished
}