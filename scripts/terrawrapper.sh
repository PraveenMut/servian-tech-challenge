#!/bin/bash

## Terraform wrapper
## This is a wrapper that ensures that all necessary env vars have been set and utilised
## It also ensures that sensitive vars like passwords aren't entirely exposed in the shell.
## Due to the nature of shell scripts, they are unable set newly formed vars in the parent
## shell, thus allowing for local scoping of vars.

## Yes, this is a bit of a contrived use. I could use terragrunt (as all terraform scripts
## converge to terragrunt :P), but as this is 1 env on a small env, this isn't necessary.
## Vault is definitely a better solution to this as well, but setting up an entire vault
## cluster with secure backends align with best practices is almost the definition of
## overkill for this project.

# Recommended usage:
# pass, lpass (both cross platform) or macosx-keygen

echo "Secure backend or enter in plain text?"
echo "Enter S to for secure backend or P for plain text entry"
read BACKEND

if [[ $BACKEND == "S" ]]; then
    echo "Enter secure backend command for password"
    echo "For example: gopass app_db/creds"
    read BACKEND_CMD
    INPUT=$(eval $BACKEND_CMD)
else
    echo "Enter plain text password"
    read -s INPUT
fi

cd ..

export GOOGLE_APPLICATION_CREDENTIALS="${PWD}/.config/terraform-admin.json"
export TF_VAR_credentials=$GOOGLE_APPLICATION_CREDENTIALS
export TF_VAR_database_username="postgres"
export TF_VAR_database_password="${INPUT}"

terraform $@