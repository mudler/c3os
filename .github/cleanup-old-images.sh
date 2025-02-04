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

cleanupOldVersionsRegion() {
  local reg=$1

  mapfile -t allAmis < <(aws --profile $AWS_PROFILE --region $reg ec2 describe-images --owners self --query 'Images[].ImageId' --output text)
  mapfile -t allTags < <(aws --profile $AWS_PROFILE --region $reg ec2 describe-images --owners self --query 'Images[].Tags' --output text)
  for img in "${allAmis[@]}"; do
    amiDeleteIfMissingTag $reg $img "KairosVersion"
  done
}

cleanupOldVersions() {
  mapfile -t regions < <(AWS ec2 describe-regions | jq -r '.Regions[].RegionName')
  for reg in "${regions[@]}"; do
    cleanupOldVersionsRegion "$reg"
  done
}
