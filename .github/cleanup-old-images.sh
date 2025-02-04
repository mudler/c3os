#!/bin/bash

set -e
set -o pipefail

set -x

amiDeleteIfMissingTag() {
  local reg=$1
  local img=$2
  local tagToCheck=$3

  # get all image tags
  mapfile -t imgTags < <(aws --profile $AWS_PROFILE --region $reg ec2 describe-images --image-ids $img --query 'Images[].Tags[]' --output text)
  TagExists=false
  for tag in "${imgTags[@]}"; do
      echo $tag
      if [[ $tag == *"$tagToCheck"* ]]; then
          TagExists=true
          break
      fi
  done

  # If the "KairosVersion" tag does not exist, delete the AMI
  if [ "$TagExists" = false ]; then
      aws --profile $AWS_PROFILE --region $reg ec2 deregister-image --image-id $img
      echo "AMI $img deleted because it does not have the '$tagToCheck' tag."
  else
      echo "AMI $img has the '$tagToCheck' tag."
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

  mapfile -t allAmis < <(aws --profile $AWS_PROFILE --region $reg ec2 describe-images --owners self --query 'Images[].ImageId' --output text)
  for img in "${allAmis[@]}"; do
    amiDeleteIfMissingTag $reg $img "KairosVersion"
  done

  highest4StableVersions=($(getHighest4StableVersions "$reg"))
  echo "Highest 4 stable versions: ${highest4StableVersions[@]}"
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
