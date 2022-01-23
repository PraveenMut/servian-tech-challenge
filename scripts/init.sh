####
# Entrypoint script of initating project
####

#!/bin/bash

set -euo pipefail

mkdir -p ../.config

# Create vars to specify relevant authN
export PROJECT_NAME="servian-gtd"
export TF_ADMIN="terraform-admin"
export TF_CREDS="${PWD}/.config/${TF_ADMIN}.json"
export BILLING_ACCOUNT="$(gcloud beta billing accounts list | grep "True" | awk '{print $1}' | tr -d '\r\n')"

# specify vars for terraform runs
export GOOGLE_PROJECT="${PROJECT_NAME}"
export GOOGLE_APPLICATION_CREDENTIALS="${TF_CREDS}"

# Create project, underlying IAM for the terraform user
echo "Creating Project..."
gcloud projects create ${PROJECT_NAME} \
    --set-as-default

echo "Linking Billing..."
gcloud beta billing projects link ${PROJECT_NAME} \
    --billing-account ${BILLING_ACCOUNT}

echo "Create Terraform Service Account..."
gcloud iam service-accounts create ${TF_ADMIN} \
    --display-name "terraform-admin-account"

echo "Fetching Keys..."
echo "WARNING: THIS IS SENSITIVE DATA. DO NOT COMMIT THE PRIVATE KEY."
gcloud iam service-accounts keys create ${TF_CREDS} \
    --iam-account ${TF_ADMIN}@${PROJECT_NAME}.iam.gserviceaccount.com

echo "Add in IAM policies for the terraform account..."
gcloud projects add-iam-policy-binding ${PROJECT_NAME} \
    --member serviceAccount:${TF_ADMIN}@${PROJECT_NAME}.iam.gserviceaccount.com \
    --role roles/viewer

gcloud projects add-iam-policy-binding ${PROJECT_NAME} \
    --member serviceAccount:${TF_ADMIN}@${PROJECT_NAME}.iam.gserviceaccount.com \
    --role roles/editor

gcloud projects add-iam-policy-binding ${PROJECT_NAME} \
    --member serviceAccount:${TF_ADMIN}@${PROJECT_NAME}.iam.gserviceaccount.com \
    --role roles/storage.admin


# Enable the serviceusage API to allow terraform to create IAM
echo "Enable the Service Usage API to allow Terraform to interact with the underlying GCP REST APIs..."
gcloud services enable serviceusage.googleapis.com

# Create bucket for remote state and set versioning
echo "Create Bucket for remote TF state..."
gsutil mb -p ${PROJECT_NAME} -l australia-southeast1 gs://servian-terraform 
gsutil versioning set on gs://servian-terraform

# Init the backend
echo "Initalising Terraform..."
cd ..
terraform init


echo "|-------------------------------------------|"
echo "|        Initialisation Complete.           |"
echo "|-------------------------------------------|"
echo ""
echo "To provision underlying resources. Run terraform plan."
echo "If satisfactory, Run a terraform apply."

echo "Afterwards, run the CI/CD pipeline."
echo "This pipeline will build and push the image to Google Artifact Repository."
echo "This pushed image will then be used by Cloud Run to serve the application."