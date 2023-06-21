#!/bin/bash

set -xe
repository='swiftwasm/swift'
workflow_name='build-toolchain.yml'
branch=$1
channel=$2
swift_source_dir="$(cd "$(dirname $0)/../.." && pwd)"

TARGETS_TO_DIST=${TARGETS_TO_DIST:?"Please set TARGETS_TO_DIST"}
targets=($TARGETS_TO_DIST)
DARWIN_TOOLCHAIN_APPLICATION_CERT=${DARWIN_TOOLCHAIN_APPLICATION_CERT:?"Please set DARWIN_TOOLCHAIN_APPLICATION_CERT"}
DARWIN_TOOLCHAIN_INSTALLER_CERT=${DARWIN_TOOLCHAIN_INSTALLER_CERT:?"Please set DARWIN_TOOLCHAIN_APPLICATION_CERT"}
DARWIN_TOOLCHAIN_NOTARIZE_EMAIL=${DARWIN_TOOLCHAIN_NOTARIZE_EMAIL:?"Please set DARWIN_TOOLCHAIN_NOTARIZE_EMAIL"}
DARWIN_TOOLCHAIN_NOTARIZE_TEAM_ID=${DARWIN_TOOLCHAIN_NOTARIZE_TEAM_ID:?"Please set DARWIN_TOOLCHAIN_NOTARIZE_TEAM_ID"}

gh_api=https://api.github.com

github() {
  curl --header "authorization: Bearer $GITHUB_TOKEN" "$@"
}

# workaround: if status=success option is given, the API doesn't return the latest runs list, so remove it temporarily.
latest_run=$(github "${gh_api}/repos/${repository}/actions/workflows/${workflow_name}/runs?branch=${branch}" \
  | jq ".workflow_runs | map(select(.head_branch == \"$branch\")) | map(select(.conclusion == \"success\")) | sort_by(.run_number) | last")

if [ -z "$latest_run" ] || [ "$latest_run" == "null" ]; then
  echo "No successful runs available"
  exit 0
fi

artifacts_url=$(echo $latest_run | jq .artifacts_url --raw-output)
head_sha=$(echo $latest_run | jq .head_sha --raw-output)

get_artifact_url() {
  local name=$1
  github $artifacts_url --fail | jq ".artifacts[] | select((.name == \"$name\") and (.expired | not)) | .archive_download_url" | sed 's/\"//g'
}

download_artifact() {
  local name=$1
  local artifact_url="$(get_artifact_url $name)"

  if [ -z "$artifact_url" ] || [ "$artifact_url" == "null" ]; then
    echo "No successfully built artifacts available for $name"
    exit 0
  fi

  github -L "$artifact_url" --fail -o "$name.zip"
}

is_released() {
  local name=$1
  local code=$(github "$gh_api/repos/$repository/releases/tags/$name" -o /dev/null -w '%{http_code}')
  test $code = 200
}

create_tag() {
  local name=$1
  local sha=$2
  local body=$(cat <<EOS
    {
      "tag": "$name",
      "message": "$name",
      "object": "$sha",
      "type": "commit"
    }
EOS
)
  github --request POST --fail \
    --url "${gh_api}/repos/${repository}/git/tags" \
    --data "$body"
}

create_release() {
  local name=$1
  local tag=$2
  local sha=$3
  local body=$(cat <<EOS
    {
      "tag_name": "$tag",
      "target_commitish": "$sha",
      "name": "$name",
      "prerelease": true
    }
EOS
)
  local response=$(github \
    --request POST --fail \
    --url "${gh_api}/repos/${repository}/releases" \
    --data "$body")
  echo $response | jq .id
}

upload_tarball() {
  local release_id=$1
  local artifact=$2
  local filename=$(basename $artifact)

  github -XPOST --fail \
    -H "Content-Length: $(stat -f%z "$artifact")" \
    -H "Content-Type: application/x-gzip" \
    --upload-file "$artifact" \
    "https://uploads.github.com/repos/$repository/releases/$release_id/assets?name=$filename"
}

sign_toolchain() {
  local darwin_toolchain=$1
  local codesign_bin="/usr/bin/codesign"

  codesign_args=(--force --verify --verbose --deep --options runtime --timestamp --sign "${DARWIN_TOOLCHAIN_APPLICATION_CERT}")
  for binary in $(find "${darwin_toolchain}" -type f); do
    if file "$binary" | grep -q "Mach-O"; then
        ${codesign_bin} "${codesign_args[@]}" "${binary}"
    fi
  done

  ${codesign_bin} "${codesign_args[@]}" "${darwin_toolchain}/"
}

create_installer() {
  local darwin_toolchain=$1
  local darwin_toolchain_name=$(basename "$darwin_toolchain")
  local darwin_toolchain_installer_package="$darwin_toolchain.pkg"
  local darwin_toolchain_install_location="/Library/Developer/Toolchains/${darwin_toolchain_name}.xctoolchain"
  local darwin_toolchain_version=$(/usr/libexec/PlistBuddy  -c "Print Version string" "$darwin_toolchain"/Info.plist)
  local darwin_toolchain_bundle_identifier=$(/usr/libexec/PlistBuddy  -c "Print CFBundleIdentifier string" "$darwin_toolchain"/Info.plist)

  "${swift_source_dir}/utils/toolchain-installer" "${darwin_toolchain}/" "${darwin_toolchain_bundle_identifier}" \
    "${DARWIN_TOOLCHAIN_INSTALLER_CERT}" "${darwin_toolchain_installer_package}" "${darwin_toolchain_install_location}" \
    "${darwin_toolchain_version}" "${swift_source_dir}/utils/darwin-installer-scripts"

  # Notarize the toolchain installer
  xcrun notarytool submit "${darwin_toolchain_installer_package}" \
      --wait \
      --apple-id "${DARWIN_TOOLCHAIN_NOTARIZE_EMAIL}" \
      --team-id "${DARWIN_TOOLCHAIN_NOTARIZE_TEAM_ID}" \
      --password "${DARWIN_TOOLCHAIN_NOTARIZE_PASSWORD}"

  xcrun stapler staple "${darwin_toolchain_installer_package}"
}

package_darwin_toolchain() {
  local toolchain_tar=$1
  local destination=$2
  local toolchain_name=$(basename $(tar tfz "$toolchain_tar" | head -n1))
  local workdir=$(mktemp -d)

  tar xfz "$toolchain_tar" -C "$workdir"
  sign_toolchain "$workdir/$toolchain_name"
  create_installer "$workdir/$toolchain_name"

  mv "$workdir/$toolchain_name.pkg" "$destination"
  rm -rf "$workdir"
}

tmp_dir=$(mktemp -d)
pushd $tmp_dir

for target in ${targets[@]}; do
  download_artifact $target-installable
  unzip $target-installable.zip
done

original_toolchain_name=$(basename $(tar tfz swift-wasm-$channel-SNAPSHOT-${targets[0]}.tar.gz | head -n1))
toolchain_name=${3:-$original_toolchain_name}

if is_released $toolchain_name; then
  echo "Latest toolchain $toolchain_name has been already released"
  exit 0
fi

for target in ${targets[@]}; do
  original_toolchain_name=$(basename $(tar tfz swift-wasm-$channel-SNAPSHOT-$target.tar.gz | head -n1))
  if [[ "$toolchain_name" != "$original_toolchain_name" ]]; then
    tar xfz swift-wasm-$channel-SNAPSHOT-$target.tar.gz
    mv "$original_toolchain_name" "$toolchain_name"
    if [[ "$target" == macos_* ]]; then
      darwin_toolchain_info_plist="$toolchain_name/Info.plist"
      if [[ -n "${DARWIN_TOOLCHAIN_DISPLAY_NAME}" ]]; then
        /usr/libexec/PlistBuddy -c "Set DisplayName '${DARWIN_TOOLCHAIN_DISPLAY_NAME}'" "${darwin_toolchain_info_plist}"
      fi
      if [[ -n "${DARWIN_TOOLCHAIN_DISPLAY_NAME_SHORT}" ]]; then
        /usr/libexec/PlistBuddy -c "Set ShortDisplayName '${DARWIN_TOOLCHAIN_DISPLAY_NAME_SHORT}'" "${darwin_toolchain_info_plist}"
      fi
    fi
    tar cfz swift-wasm-$channel-SNAPSHOT-$target.tar.gz "$toolchain_name"
    rm -rf "$toolchain_name"
  fi
done

release_packages=()

for target in ${targets[@]}; do
  if [[ "$target" == macos_* ]]; then
    package_darwin_toolchain "swift-wasm-$channel-SNAPSHOT-$target.tar.gz" "$toolchain_name-$target.pkg"
    release_packages=("$toolchain_name-$target.pkg" "${release_packages[@]}")
  else
    mv swift-wasm-$channel-SNAPSHOT-$target.tar.gz "$toolchain_name-$target.tar.gz"
    release_packages=("$toolchain_name-$target.tar.gz" "${release_packages[@]}")
  fi
done

create_tag $toolchain_name $head_sha
release_id=$(create_release $toolchain_name $toolchain_name $head_sha)

for package in ${release_packages[@]}; do
  upload_tarball $release_id "$package"
done

dispatch_release_event() {
  local release_id=$1
  local body=$(cat <<EOS
    {
      "event_type": "release_created",
      "client_payload": {
        "toolchain_channel": "$channel",
        "ref": "$head_sha",
        "release_id": "$release_id"
      }
    }
EOS
)

  curl --header "authorization: Bearer $BUILDBOT_GITHUB_TOKEN" \
    --request POST --fail \
    --url "${gh_api}/repos/swiftwasm/swiftwasm-buildbot/dispatches" \
    --data "$body"
}

if [[ ! -z "$BUILDBOT_GITHUB_TOKEN" ]]; then
  dispatch_release_event "$release_id"
fi

popd
