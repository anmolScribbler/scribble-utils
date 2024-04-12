#!/bin/bash

# Please change values of these variables
SUBSCRIPTION_ID="<subscription id>"
APPLICATION_CLIENT_ID="<application id>"
RESOURCE_GROUP="<resource-group>"

# Function to display usage instructions
display_usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --assign-role        Assign a new role"
  echo "  --remove-role        Remove an existing role"
  echo "  --help              Display usage instructions"
  echo "This script creates a role and assigns permissions required for the deployment of the scribble platform on Azure."
  echo "Before running the script, make sure to configure the following variables:"
  echo "  SUBSCRIPTION_ID=\"YOUR_SUBSCRIPTION_ID\""
  echo "  APPLICATION_CLIENT_ID=\"YOUR_APPLICATION_CLIENT_ID\""
  echo "  RESOURCE_GROUP=\"YOUR_RESOURCE_GROUP_NAME\""
}

loading_icon() {
    local load_interval="${1}"
    local loading_message="${2}"
    local elapsed=0
    local loading_animation=( '—' "\\" '|' '/' )

    echo -n "${loading_message} "

    # This part is to make the cursor not blink
    # on top of the animation while it lasts
    tput civis
    trap "tput cnorm" EXIT
    while [ "${load_interval}" -ne "${elapsed}" ]; do
        for frame in "${loading_animation[@]}" ; do
            printf "%s\b" "${frame}"
            sleep 0.25
        done
        elapsed=$(( elapsed + 1 ))
    done
    printf " \b\n"
}

wait_and_list_role() {
  loading_message="Waiting for azure to reflect the new role"
  loading_icon 60 "${loading_message}"
  local role_added=$(az role definition list --query "[?name=='$1'].name" -o json)
  while [[ "${role_added}" == "[]" ]]; do
    loading_icon 15 "${loading_message}"
    role_added=$(az role definition list --query "[?name=='$1'].name" -o json)
  done
  az role definition list --query "[?name=='$1']" -o json
  echo
}

wait_and_list_role_assignment() {
  loading_message="Waiting for azure to reflect the new role assignment"
  local role_polled=$(az role assignment list --role "$1" --assignee "$APPLICATION_CLIENT_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
  --query "[?name=='$2'].name" -o json)
  while [[ "${role_assignment}" == "[]" ]]; do
    loading_icon 15 "${loading_message}"
    role_assignment=$(az role assignment list --role "$1" --assignee "$APPLICATION_CLIENT_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    --query "[?name=='$2'].name" -o json)
  done
  az role assignment list --role "$1" --assignee "$APPLICATION_CLIENT_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
  --query "[?name=='$2']" -o json
  echo
}


# Function to handle assigning a new role
assign_role() {
  echo "Assigning a new role..."
  echo "Checking if the role already exists..."
  loading_icon 60 "Waiting 60 sec for azure to reflect the role definitions"
  # Check if the role already exists
  echo "Role name: $role_name"
  existing_role=$(az role definition list --query "[?roleName=='$role_name'].name" -o tsv)

  if [[ -n $existing_role ]]; then
    role_disk_manager=$existing_role
    echo "Role ($role_name) already exists. Skipping role creation."
    echo "Matching role: $role_disk_manager"
    az role definition list --query "[?name=='$role_disk_manager']" --output json
    echo
  else
    echo "Creating role (Disk, snapshots manager for the scribble resource group)"
    role_disk_manager=$(az role definition create --query "name" --output tsv --role-definition '{
      "Name": "'"${role_name}"'",
      "Description": "Create, delete disks and snapshots",
      "Actions": [
        "Microsoft.Compute/disks/read",
        "Microsoft.Compute/disks/write",
        "Microsoft.Compute/disks/delete",
        "Microsoft.Compute/disks/beginGetAccess/action",
        "Microsoft.Compute/snapshots/read",
        "Microsoft.Compute/snapshots/write",
        "Microsoft.Compute/snapshots/delete",
        "Microsoft.Compute/virtualMachines/read",
        "Microsoft.Compute/virtualMachines/write",
        "Microsoft.Network/networkInterfaces/join/action",
        "Microsoft.Resources/subscriptions/resourcegroups/read"
      ],
      "AssignableScopes": ["/subscriptions/'"$SUBSCRIPTION_ID"'/resourceGroups/'"$RESOURCE_GROUP"'"]
    }')
    echo "Role created with name: $role_disk_manager"
    wait_and_list_role $role_disk_manager
  fi

  # Check if role assignment already exists
  existing_assignment=$(az role assignment list --role "$role_disk_manager" --assignee "$APPLICATION_CLIENT_ID" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[].name" -o tsv)

  if [[ -n $existing_assignment ]]; then
    echo "Role assignment already exists. Skipping role assignment creation."
    echo "Role assignment exists with name: $existing_assignment"
    az role assignment list --role "$role_disk_manager" --assignee "$APPLICATION_CLIENT_ID" \
     --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
     --query "[?name=='$existing_assignment']" -o json
    echo
  else
    echo "Creating role assignment for the role (Disk, snapshots manager for the scribble resource group)"
    role_assignment=$(az role assignment create --role "$role_disk_manager" --assignee "$APPLICATION_CLIENT_ID" \
    --query "name" --output tsv \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP")
    echo "Role assignment created with name: $role_assignment"
    wait_and_list_role_assignment $role_disk_manager $role_assignment
    echo
  fi
}


wait_till_role_removed() {
  loading_message="Waiting for azure to reflect the role deletion"
  local role_deleted=$(az role definition list --query "[?name=='$1'].name" -o json)
  # Check for empty array as indicator of the role being removed
  while [ "${role_deleted}" != "[]" ]; do
    loading_icon 15 "${loading_message}"
    role_deleted=$(az role definition list --query "[?name=='$1'].name" -o json)
  done
  echo "Role removed: $1"
}

wait_till_role_assignment_removed() {
  loading_message="Waiting for azure to reflect the role assignment deletion"
  local role_assignment=$(az role assignment list --role "$1" --assignee "$APPLICATION_CLIENT_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
  --query "[?name=='$2'].name" -o json)
  while [[ "${role_assignment}" != "[]"  ]]; do
    loading_icon 15 "${loading_message}"
    role_assignment=$(az role assignment list --role "$1" --assignee "$APPLICATION_CLIENT_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    --query "[?name=='$2'].name" -o json)
  done
  echo "Role assignment removed: $1"
}

# Function to handle removing an existing role
remove_role() {
  echo "Removing an existing role..."
  loading_icon 60 "Waiting 60 sec for azure to reflect the role definitions"
  # Check if the role already exists
  existing_role=$(az role definition list --query "[?roleName=='$role_name'].name" -o tsv)

  if [[ -n $existing_role ]]; then
    role_disk_manager=$existing_role
    echo "Role ($role_name) found."

    # Display role definition JSON
    echo "Role Definition JSON:"
    az role definition list --query "[?name=='$role_disk_manager']" -o json
    echo

    read -p "Are you sure you want to delete this role? (yes/no): " answer
    if [[ $answer == "yes" ]]; then
      # Check if role assignment exists
      role_assignment=$(az role assignment list --role "$role_disk_manager" --assignee "$APPLICATION_CLIENT_ID" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[].name" -o tsv)

      if [[ -n $role_assignment ]]; then
          echo "Role assignment found:"
          az role assignment list --role "$role_disk_manager" --assignee "$APPLICATION_CLIENT_ID"\
           --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"\
           --query "[?name=='$role_assignment']" -o json
          echo

          read -p "Are you sure you want to delete this role assignment? (yes/no): " answer_role_assignment

          if [[ $answer_role_assignment == "yes" ]]; then
              echo "Deleting role assignment for the role ($role_name)"
              az role assignment delete --role "$role_disk_manager" --assignee "$APPLICATION_CLIENT_ID" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
              wait_till_role_assignment_removed $role_disk_manager $role_assignment
          else
              echo "Role assignment deletion aborted."
          fi
      else
          echo "Role assignment does not exist. No action needed."
      fi
      echo "Now removing the role ($role_name)"
      az role definition delete --name "$role_disk_manager"
      wait_till_role_removed $role_disk_manager
    else
      echo "Role deletion aborted."
    fi
  else
    echo "Role (Disk, snapshots manager for the scribble resource group) does not exist. No action needed."
  fi
}


role_name="Disk and snapshots manager for the  resource group $RESOURCE_GROUP"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --assign-role)
      action="assign-role"
      ;;
    --remove-role)
      action="remove-role"
      ;;
    --help)
      display_usage
      exit 0
      ;;
    *)
      echo "Invalid option: $1" >&2
      display_usage
      exit 1
      ;;
  esac
  shift
done

shift $((OPTIND - 1))

# Perform actions based on the chosen sub-command
case $action in
  "assign-role")
    assign_role
    ;;
  "remove-role")
    remove_role
    ;;
  *)
    echo "Invalid sub-command. Use --help for usage instructions."
    exit 1
    ;;
esac
