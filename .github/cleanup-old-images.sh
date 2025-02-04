#!/bin/bash

set -e
set -o pipefail

set -x

amiDeleteIfNotInVersionList() {
  local reg=$1
  local img=$2
  shift 2
  local versionList=("$@")

  # get all image tags
  mapfile -t imgTags < <(aws --profile $AWS_PROFILE --region $reg ec2 describe-images --image-ids $img --query 'Images[].Tags[]' --output text)
  TagExists=false
  for tag in "${imgTags[@]}"; do
    for tagToCheck in "${versionList[@]}"; do
      if [[ $tag == *"$tagToCheck"* ]]; then
        echo "AMI $img has the '$tagToCheck' tag. Skipping cleanup."
        TagExists=true
        break
      fi
    done
  done

  # If the "KairosVersion" tag does not exist, delete the AMI
  if [ "$TagExists" = false ]; then
      # TODO: Uncomment this line to delete the AMI
      #aws --profile $AWS_PROFILE --region $reg ec2 deregister-image --image-id $img
      echo "AMI $img deleted because it does not match any of the versions: '${versionList[@]}'."
  fi
}

getHighest4StableVersions() {
  local reg=$1
  local kairosVersions
  local stableVersions=()
  local sortedVersions
  local highest4StableVersions

  # Get all Kairos versions
  mapfile -t kairosVersions < <(aws --profile "$AWS_PROFILE" --region "$reg" ec2 describe-images --owners self --query 'Images[].Tags[?Key==`KairosVersion`].Value' --output text)

  # Filter out non-stable versions (those containing '-rc')
  for version in "${kairosVersions[@]}"; do
    if [[ ! $version =~ -rc ]]; then
      stableVersions+=("$version")
    fi
  done

  # Sort the stable versions and keep only the highest 4
  IFS=$'\n' sortedVersions=($(sort -V <<<"${stableVersions[*]}"))
  unset IFS
  highest4StableVersions=("${sortedVersions[@]: -4}")

  # Return the highest 4 stable versions
  echo "${highest4StableVersions[@]}"
}

cleanupOldVersionsRegion() {
  local reg=$1

  highest4StableVersions=($(getHighest4StableVersions "$reg"))
  echo "Highest 4 stable versions: ${highest4StableVersions[@]}"

  mapfile -t allAmis < <(aws --profile $AWS_PROFILE --region $reg ec2 describe-images --owners self --query 'Images[].ImageId' --output text)
  for img in "${allAmis[@]}"; do
    amiDeleteIfNotInVersionList $reg $img "${highest4StableVersions[@]}"
  done

  # TODO:
  # - Delete all AMIs that are not in the highest 4 stable versions
  # - Cleanup snapshots that don't have an associated AMI
  # - Cleanup s3 files that don't have an associated AMI
}

cleanupOldVersions() {
  mapfile -t regions < <(AWS ec2 describe-regions | jq -r '.Regions[].RegionName')
  for reg in "${regions[@]}"; do
    cleanupOldVersionsRegion "$reg"
  done
}
