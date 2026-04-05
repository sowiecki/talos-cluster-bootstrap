#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
TRUENAS_HOST="${TRUENAS_HOST:-192.168.1.32}"
TRUENAS_API_KEY="${TRUENAS_API_KEY}"
POOL="${TRUENAS_POOL:-Uldaman}"
DATASET="${TRUENAS_DATASET:-k8s/nfs/v}"
ALLOWED_NETWORK="${TRUENAS_ALLOWED_NETWORK:-192.168.1.0/24}"

API_URL="https://${TRUENAS_HOST}/api/v2.0"

# ----------------------------------------------------------------------
# Helper functions
# ----------------------------------------------------------------------
error_exit() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "📦 Installing jq..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        else
            error_exit "Cannot install jq. Please install manually."
        fi
    fi
}

api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    curl -s -k -X "$method" \
        -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "${API_URL}${endpoint}"
}

# Check if a dataset exists by listing all datasets and filtering
dataset_exists() {
    local ds_name="$1"
    local all_datasets
    all_datasets=$(api_request GET "/pool/dataset" "")
    echo "$all_datasets" | jq -e ".[] | select(.name == \"$ds_name\")" >/dev/null 2>&1
}

# Create dataset recursively if it doesn't exist
create_dataset_path() {
    local full_path="$1"
    local pool="${full_path%%/*}"
    local remainder="${full_path#*/}"
    local current="${pool}"
    local parts=(${remainder//\// })
    for part in "${parts[@]}"; do
        current="${current}/${part}"
        if dataset_exists "$current"; then
            echo "✅ Dataset $current already exists."
        else
            echo "🔧 Creating dataset $current..."
            # Correct payload: aclmode must be DISCARD when acltype is POSIX
            data=$(jq -n --arg name "$current" \
                '{name: $name, type: "FILESYSTEM", aclmode: "DISCARD", acltype: "POSIX"}')
            create_response=$(api_request POST "/pool/dataset" "$data")
            if ! echo "$create_response" | jq -e '.id' >/dev/null 2>&1; then
                error_exit "Failed to create dataset $current. Response: $create_response"
            fi
            echo "✅ Dataset $current created."
            sleep 2
        fi
    done
}

# ----------------------------------------------------------------------
# 1. Install jq and check connectivity
# ----------------------------------------------------------------------
install_jq

echo "🔍 Checking TrueNAS API connectivity..."
if ! api_request GET "/system/info" "" | jq -e '.version' >/dev/null 2>&1; then
    error_exit "Failed to connect to TrueNAS API. Check host and API key."
fi
echo "✅ API reachable."

# ----------------------------------------------------------------------
# 2. Ensure NFS service is running
# ----------------------------------------------------------------------
echo "🔍 Checking NFS service..."
nfs_status=$(api_request GET "/service?service=nfs" "" | jq -r '.[0].state')
if [ "$nfs_status" != "RUNNING" ]; then
    echo "▶️ Starting NFS service..."
    api_request POST "/service/start" '{"service": "nfs"}' >/dev/null
    sleep 3
fi

# ----------------------------------------------------------------------
# 3. Create dataset recursively
# ----------------------------------------------------------------------
create_dataset_path "${POOL}/${DATASET}"

# ----------------------------------------------------------------------
# 4. Retrieve the exact mountpoint of the dataset
# ----------------------------------------------------------------------
echo "🔍 Retrieving mountpoint for dataset ${POOL}/${DATASET}..."
all_datasets=$(api_request GET "/pool/dataset" "")
mountpoint=$(echo "$all_datasets" | jq -r ".[] | select(.name == \"${POOL}/${DATASET}\") | .mountpoint")
if [ -z "$mountpoint" ] || [ "$mountpoint" = "null" ]; then
    error_exit "Could not retrieve mountpoint for dataset ${POOL}/${DATASET}. Response: $all_datasets"
fi
echo "✅ Mountpoint is: $mountpoint"

# ----------------------------------------------------------------------
# 5. Create NFS share if missing
# ----------------------------------------------------------------------
echo "🔍 Checking NFS share for ${mountpoint}..."
all_shares=$(api_request GET "/sharing/nfs" "")
share_exists=$(echo "$all_shares" | jq -e ".[] | select(.path == \"$mountpoint\")" >/dev/null 2>&1 && echo "true" || echo "false")

if [ "$share_exists" == "false" ]; then
    echo "🔧 Creating NFS share for ${mountpoint}..."
    data=$(jq -n --arg path "$mountpoint" --arg network "$ALLOWED_NETWORK" \
        '{path: $path, networks: [$network], maproot_user: "root", maproot_group: "wheel", enabled: true}')
    create_response=$(api_request POST "/sharing/nfs" "$data")
    if ! echo "$create_response" | jq -e '.id' >/dev/null 2>&1; then
        error_exit "NFS share creation failed. Response: $create_response"
    fi
    echo "✅ NFS share created (ID: $(echo "$create_response" | jq -r '.id'))."
    sleep 3
else
    echo "✅ NFS share already exists."
fi

# ----------------------------------------------------------------------
# 6. Restart NFS service to apply changes
# ----------------------------------------------------------------------
echo "🔄 Restarting NFS service..."
api_request POST "/service/restart" '{"service": "nfs"}' >/dev/null
sleep 5

# ----------------------------------------------------------------------
# 7. Verify share appears in the API again
# ----------------------------------------------------------------------
for i in {1..5}; do
    all_shares=$(api_request GET "/sharing/nfs" "")
    if echo "$all_shares" | jq -e ".[] | select(.path == \"$mountpoint\")" >/dev/null; then
        echo "✅ NFS share is active and exported."
        break
    fi
    if [ $i -eq 5 ]; then
        error_exit "NFS share was created but not exported after multiple attempts."
    fi
    echo "⏳ Waiting for share to appear (attempt $i/5)..."
    sleep 5
done

# ----------------------------------------------------------------------
# 8. Optional: test with showmount
# ----------------------------------------------------------------------
if command -v showmount &> /dev/null; then
    echo "🔍 Testing export via showmount..."
    if showmount -e "$TRUENAS_HOST" | grep -q "$mountpoint"; then
        echo "✅ Export visible via showmount."
    else
        echo "⚠️  Export not visible via showmount (but API says it's there)."
    fi
else
    echo "💡 Install nfs-common to use showmount for verification."
fi

echo "🎉 TrueNAS NFS setup completed successfully."