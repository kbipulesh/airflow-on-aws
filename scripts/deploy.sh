#!/usr/bin/env bash

IMAGE_NAME=$1
ENVIRONMENT=$2
AWS_ECR_REPO=${AWS_ACCOUNT}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com

### ECR - build images and push to remote repository

echo "Building image: ${IMAGE_NAME}:latest"
docker build --rm -t ${IMAGE_NAME}:latest .

eval $(aws ecr get-login-password --region ${AWS_DEFAULT_REGION})

# tag and push image using latest
docker tag ${IMAGE_NAME}:latest ${AWS_ECR_REPO}/${IMAGE_NAME}:latest
docker push ${AWS_ECR_REPO}/${IMAGE_NAME}:latest

# generate a random commit hash
# COMMIT_HASH=$(hexdump -n 16 -v -e '/1 "%02X"' -e '/16 "\n"' /dev/urandom)
COMMIT_HASH=$(date +"build-%Y%m%d-%H%MET")

# tag and push image with commit hash
docker tag ${IMAGE_NAME}:latest ${AWS_ECR_REPO}/${IMAGE_NAME}:${COMMIT_HASH}
docker push ${AWS_ECR_REPO}/${IMAGE_NAME}:${COMMIT_HASH}

# terraform apply -var "image_version=$COMMIT_HASH" -auto-approve
terraform -chdir=infrastructure/${ENVIRONMENT} apply -var "image_version=latest" -auto-approve
