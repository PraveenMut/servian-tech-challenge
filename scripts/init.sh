####
# Entrypoint script of initating project
####

#!/bin/bash

set -euo pipefail

mkdir -p ${PWD}/.config


# Create vars to specify relevant authN
export PROJECT_NAME="servian-gtd-app"
export TF_ADMIN="${PROJECT_NAME}-terraform-admin"
export TF_CREDS="${PWD}/.config/${TF_ADMIN}.json"
export BILLING_ACCOUNT="$(gcloud beta billing accounts list | grep "True" | awk '{print $1}' | tr -d '\r\n')"

# specify vars for terraform runs
export GOOGLE_PROJECT="${PROJECT_NAME}"
export GOOGLE_APPLICATION_CREDENTIALS="${TF_CREDS}"

# Create project, underlying IAM for the terraform user
gcloud projects create ${PROJECT_NAME} \ 
    --set-as-default

gcloud beta billing projects link ${PROJECT_NAME} \ 
    --billing-account ${BILLING_ACCOUNT}

gcloud iam service-accounts create terraform \ 
    --display-name "terraform-admin-account"

gcloud iam service-accounts keys create ${TF_CREDS} \ 
    --iam-account terraform-admin-account@${PROJECT_NAME}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding ${PROJECT_NAME} \ 
    --member serviceAccount:terraform-admin-account@${PROJECT_NAME}.iam.gserviceaccount.com \ 
    --role roles/viewer

gcloud projects add-iam-policy-binding ${PROJECT_NAME} \ 
    --member serviceAccount:terraform-admin-account@${PROJECT_NAME}.iam.gserviceaccount.com \ 
    --role roles/editor

gcloud projects add-iam-policy-binding ${PROJECT_NAME} \ 
    --member serviceAccount:terraform-admin-account@${PROJECT_NAME}.iam.gserviceaccount.com \ 
    --role roles/storage.admin


# Enable the serviceusage API to allow terraform to create IAM
gcloud services enable serviceusage.googleapis.com

# Create bucket for remote state and set versioning
gsutil mb -p ${PROJECT_NAME} gs://servian-terraform
gsutil versioning set on gs://servian-terraform