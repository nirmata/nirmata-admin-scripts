#!/bin/bash

# Kubernetes Image Migration Script
# Migrates container images in Kubernetes resources with granular control and dry-run support

set -euo pipefail

# Default values
NAMESPACE=""
SOURCE_REGISTRY=""
DESTINATION_REGISTRY=""
IMAGE_PULL_SECRET="artifactory-secret"
DRY_RUN=false
INTERACTIVE=false
OUTPUT_PLAN=""
OUTPUT_CSV=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Help function
show_help() {
    cat << EOF
Kubernetes Image Migration Tool

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -n, --namespace NAMESPACE       Target namespace (required)
    -s, --source-registry REGISTRY Source registry to migrate from (required)
    -d, --dest-registry REGISTRY   Destination registry to migrate to (required)
    -p, --image-pull-secret SECRET ImagePullSecret name to add (default: artifactory-secret)
    --dry-run                      Perform a dry run without making changes
    -i, --interactive              Ask for confirmation before each migration
    -o, --output-plan FILE         Output migration plan to file (JSON format)
    --output-csv FILE              Output migration plan to CSV file for auditing
    -v, --verbose                  Enable verbose logging
    -h, --help                     Show this help message

EXAMPLES:
    # Dry run migration for specific namespace with CSV output
    $0 --dry-run \\
       --namespace production \\
       --source-registry legacy-docker-repo.company.net \\
       --dest-registry artifactory.company.net/docker-virtual \\
       --output-csv migration-audit.csv

    # Interactive migration for specific namespace
    $0 --interactive \\
       --namespace test-migration-1 \\
       --source-registry legacy-docker-repo.company.net \\
       --dest-registry ghcr.io/myorganization

    # Migration with custom imagePullSecret and CSV audit
    $0 --namespace app-namespace \\
       --source-registry legacy-docker-repo.company.net \\
       --dest-registry ghcr.io/myorganization \\
       --image-pull-secret my-registry-secret \\
       --output-csv audit-report.csv

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -s|--source-registry)
                SOURCE_REGISTRY="$2"
                shift 2
                ;;
            -d|--dest-registry)
                DESTINATION_REGISTRY="$2"
                shift 2
                ;;
            -p|--image-pull-secret)
                IMAGE_PULL_SECRET="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -o|--output-plan)
                OUTPUT_PLAN="$2"
                shift 2
                ;;
            --output-csv)
                OUTPUT_CSV="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$SOURCE_REGISTRY" ]]; then
        log_error "Source registry is required. Use -s or --source-registry"
        exit 1
    fi

    if [[ -z "$DESTINATION_REGISTRY" ]]; then
        log_error "Destination registry is required. Use -d or --dest-registry"
        exit 1
    fi

    if [[ -z "$NAMESPACE" ]]; then
        log_error "Namespace is required. Use -n or --namespace to specify target namespace"
        exit 1
    fi
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

# Get list of namespaces
get_namespaces() {
    # Always return the specific namespace since we now require it
    echo "$NAMESPACE"
}

# Check if imagePullSecret exists in namespace
check_image_pull_secret_exists() {
    local namespace=$1
    kubectl get secret "$IMAGE_PULL_SECRET" -n "$namespace" &> /dev/null
}

# Get current imagePullSecrets from a resource
get_current_image_pull_secrets() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    local jsonpath=""
    case "$resource_type" in
        deployment|statefulset|daemonset)
            jsonpath='{.spec.template.spec.imagePullSecrets[*].name}'
            ;;
        cronjob)
            jsonpath='{.spec.jobTemplate.spec.template.spec.imagePullSecrets[*].name}'
            ;;
        pod|job)
            jsonpath='{.spec.imagePullSecrets[*].name}'
            ;;
        *)
            return
            ;;
    esac
    
    kubectl get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath="$jsonpath" 2>/dev/null || true
}

# Extract images from a resource
extract_images_from_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local temp_file="/tmp/k8s_resource_$$.json"
    
    kubectl get "$resource_type" "$resource_name" -n "$namespace" -o json > "$temp_file"
    
    local images=()
    local jsonpath=""
    
    case "$resource_type" in
        deployment|statefulset|daemonset)
            jsonpath='{.spec.template.spec.containers[*].image} {.spec.template.spec.initContainers[*].image}'
            ;;
        cronjob)
            jsonpath='{.spec.jobTemplate.spec.template.spec.containers[*].image} {.spec.jobTemplate.spec.template.spec.initContainers[*].image}'
            ;;
        pod|job)
            jsonpath='{.spec.containers[*].image} {.spec.initContainers[*].image}'
            ;;
        *)
            rm -f "$temp_file"
            return
            ;;
    esac
    
    local all_images
    all_images=$(kubectl get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath="$jsonpath" 2>/dev/null || true)
    
    for image in $all_images; do
        if [[ "$image" == *"$SOURCE_REGISTRY"* ]]; then
            local dest_image="${image/$SOURCE_REGISTRY/$DESTINATION_REGISTRY}"
            echo "$namespace|$resource_type|$resource_name|$image|$dest_image"
        fi
    done
    
    rm -f "$temp_file"
}

# Scan namespace for images
scan_namespace_for_images() {
    local namespace=$1
    log_info "Scanning namespace: $namespace" >&2
    
    local resource_types=("deployments" "statefulsets" "daemonsets" "pods" "cronjobs" "jobs")
    local found_images=()
    
    for resource_type in "${resource_types[@]}"; do
        log_verbose "Scanning $resource_type in namespace $namespace" >&2
        
        local resources
        resources=$(kubectl get "$resource_type" -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
        
        if [[ -n "$resources" ]]; then
            for resource_name in $resources; do
                local images
                images=$(extract_images_from_resource "${resource_type%s}" "$resource_name" "$namespace")
                if [[ -n "$images" ]]; then
                    echo "$images"
                fi
            done
        fi
    done
}

# Scan cluster for images
scan_cluster() {
    log_info "Scanning cluster for images matching source registry: $SOURCE_REGISTRY" >&2
    
    local all_images=()
    local namespaces
    namespaces=$(get_namespaces)
    
    for ns in $namespaces; do
        local ns_images
        ns_images=$(scan_namespace_for_images "$ns")
        if [[ -n "$ns_images" ]]; then
            echo "$ns_images"
        fi
    done
}

# Display migration plan
display_migration_plan() {
    local images_file=$1
    
    if [[ ! -s "$images_file" ]]; then
        log_warning "No images found matching the source registry pattern."
        return 1
    fi
    
    echo
    echo "================================================================================"
    echo "                              MIGRATION PLAN"
    echo "================================================================================"
    echo "Source Registry: $SOURCE_REGISTRY"
    echo "Destination Registry: $DESTINATION_REGISTRY"
    echo "Image Pull Secret: $IMAGE_PULL_SECRET"
    echo "================================================================================"
    
    local current_namespace=""
    local count=0
    
    while IFS='|' read -r namespace resource_type resource_name source_image dest_image; do
        if [[ "$namespace" != "$current_namespace" ]]; then
            echo
            echo "Namespace: $namespace"
            echo "----------------------------------------"
            current_namespace="$namespace"
        fi
        
        echo "  Resource: $resource_type/$resource_name"
        echo "    FROM: $source_image"
        echo "    TO:   $dest_image"
        echo
        ((count++))
    done < "$images_file"
    
    echo "================================================================================"
    echo "Total images to migrate: $count"
    echo "================================================================================"
    
    return 0
}

# Create JSON migration plan
create_json_plan() {
    local images_file=$1
    local output_file=$2
    
    cat > "$output_file" << EOF
{
  "config": {
    "namespace": "$NAMESPACE",
    "source_registry": "$SOURCE_REGISTRY",
    "destination_registry": "$DESTINATION_REGISTRY",
    "image_pull_secret": "$IMAGE_PULL_SECRET"
  },
  "images": [
EOF
    
    local first=true
    while IFS='|' read -r namespace resource_type resource_name source_image dest_image; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$output_file"
        fi
        
        cat >> "$output_file" << EOF
    {
      "namespace": "$namespace",
      "resource_type": "$resource_type",
      "resource_name": "$resource_name",
      "source": "$source_image",
      "destination": "$dest_image"
    }
EOF
    done < "$images_file"
    
    echo >> "$output_file"
    echo "  ]" >> "$output_file"
    echo "}" >> "$output_file"
}

# Create CSV migration plan for auditing
create_csv_plan() {
    local images_file=$1
    local output_file=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local status="${3:-Planned}"
    
    # Create CSV header
    cat > "$output_file" << EOF
Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status
EOF
    
    # Add data rows
    while IFS='|' read -r namespace resource_type resource_name source_image dest_image; do
        echo "$timestamp,$namespace,$resource_type,$resource_name,\"$source_image\",\"$dest_image\",$SOURCE_REGISTRY,$DESTINATION_REGISTRY,$IMAGE_PULL_SECRET,$status" >> "$output_file"
    done < "$images_file"
}

# Create rollback CSV automatically
create_rollback_backup() {
    local images_file=$1
    local base_name="${2:-migration}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local rollback_file="${base_name}_rollback_${timestamp}.csv"
    
    log_info "Creating rollback backup: $rollback_file"
    create_csv_plan "$images_file" "$rollback_file" "Executed"
    log_success "Rollback backup saved to: $rollback_file"
    echo "$rollback_file"
}

# Update container image in resource
update_container_image() {
    local namespace=$1
    local resource_type=$2
    local resource_name=$3
    local source_image=$4
    local dest_image=$5
    
    log_verbose "Updating image in $resource_type/$resource_name"
    
    # Get current resource JSON
    local temp_file="/tmp/k8s_patch_$$.json"
    kubectl get "$resource_type" "$resource_name" -n "$namespace" -o json > "$temp_file"
    
    # Create patch based on resource type
    local patch_file="/tmp/k8s_patch_update_$$.json"
    
    case "$resource_type" in
        deployment|statefulset|daemonset)
            # Update containers and initContainers
            jq --arg source "$source_image" --arg dest "$dest_image" '
                (.spec.template.spec.containers[]? | select(.image == $source) | .image) = $dest |
                (.spec.template.spec.initContainers[]? | select(.image == $source) | .image) = $dest
            ' "$temp_file" > "$patch_file"
            ;;
        cronjob)
            jq --arg source "$source_image" --arg dest "$dest_image" '
                (.spec.jobTemplate.spec.template.spec.containers[]? | select(.image == $source) | .image) = $dest |
                (.spec.jobTemplate.spec.template.spec.initContainers[]? | select(.image == $source) | .image) = $dest
            ' "$temp_file" > "$patch_file"
            ;;
        pod|job)
            jq --arg source "$source_image" --arg dest "$dest_image" '
                (.spec.containers[]? | select(.image == $source) | .image) = $dest |
                (.spec.initContainers[]? | select(.image == $source) | .image) = $dest
            ' "$temp_file" > "$patch_file"
            ;;
    esac
    
    # Apply the patch
    local kubectl_cmd="kubectl replace -f $patch_file"
    if [[ "$DRY_RUN" == "true" ]]; then
        kubectl_cmd="$kubectl_cmd --dry-run=client"
    fi
    
    if eval "$kubectl_cmd" &> /dev/null; then
        log_success "Image updated successfully"
    else
        log_error "Failed to update image"
        rm -f "$temp_file" "$patch_file"
        return 1
    fi
    
    rm -f "$temp_file" "$patch_file"
    return 0
}

# Add imagePullSecret to resource
add_image_pull_secret() {
    local namespace=$1
    local resource_type=$2
    local resource_name=$3
    
    # Check if secret exists in namespace
    if ! check_image_pull_secret_exists "$namespace"; then
        log_warning "imagePullSecret '$IMAGE_PULL_SECRET' does not exist in namespace '$namespace'"
        log_info "You may need to create the secret first:"
        log_info "kubectl create secret docker-registry $IMAGE_PULL_SECRET \\"
        log_info "  --docker-server=<your-registry> \\"
        log_info "  --docker-username=<username> \\"
        log_info "  --docker-password=<password> \\"
        log_info "  -n $namespace"
        return 0
    fi
    
    # Check if imagePullSecret already exists
    local current_secrets
    current_secrets=$(get_current_image_pull_secrets "$resource_type" "$resource_name" "$namespace")
    
    if [[ "$current_secrets" == *"$IMAGE_PULL_SECRET"* ]]; then
        log_verbose "imagePullSecret '$IMAGE_PULL_SECRET' already exists in $resource_type/$resource_name"
        return 0
    fi
    
    log_verbose "Adding imagePullSecret to $resource_type/$resource_name"
    
    # Create patch for imagePullSecrets
    local patch=""
    case "$resource_type" in
        deployment|statefulset|daemonset)
            if [[ -n "$current_secrets" ]]; then
                patch='{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"'$current_secrets'"},{"name":"'$IMAGE_PULL_SECRET'"}]}}}}'
            else
                patch='{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"'$IMAGE_PULL_SECRET'"}]}}}}'
            fi
            ;;
        cronjob)
            if [[ -n "$current_secrets" ]]; then
                patch='{"spec":{"jobTemplate":{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"'$current_secrets'"},{"name":"'$IMAGE_PULL_SECRET'"}]}}}}}}'
            else
                patch='{"spec":{"jobTemplate":{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"'$IMAGE_PULL_SECRET'"}]}}}}}}'
            fi
            ;;
        pod|job)
            if [[ -n "$current_secrets" ]]; then
                patch='{"spec":{"imagePullSecrets":[{"name":"'$current_secrets'"},{"name":"'$IMAGE_PULL_SECRET'"}]}}'
            else
                patch='{"spec":{"imagePullSecrets":[{"name":"'$IMAGE_PULL_SECRET'"}]}}'
            fi
            ;;
    esac
    
    local kubectl_cmd="kubectl patch $resource_type $resource_name -n $namespace --type=merge -p '$patch'"
    if [[ "$DRY_RUN" == "true" ]]; then
        kubectl_cmd="$kubectl_cmd --dry-run=client"
    fi
    
    if eval "$kubectl_cmd" &> /dev/null; then
        log_success "imagePullSecret added successfully"
        return 0
    else
        log_error "Failed to add imagePullSecret"
        return 1
    fi
}

# Migrate single image
migrate_image() {
    local namespace=$1
    local resource_type=$2
    local resource_name=$3
    local source_image=$4
    local dest_image=$5
    
    local prefix=""
    if [[ "$DRY_RUN" == "true" ]]; then
        prefix="[DRY-RUN] "
    fi
    
    log_info "${prefix}Migrating $resource_type/$resource_name in namespace $namespace"
    log_info "  FROM: $source_image"
    log_info "  TO:   $dest_image"
    
    # Update the image
    if ! update_container_image "$namespace" "$resource_type" "$resource_name" "$source_image" "$dest_image"; then
        return 1
    fi
    
    # Add imagePullSecret
    if ! add_image_pull_secret "$namespace" "$resource_type" "$resource_name"; then
        log_warning "Failed to add imagePullSecret, but image was updated"
    fi
    
    return 0
}

# Execute migration
execute_migration() {
    local images_file=$1
    
    if [[ ! -s "$images_file" ]]; then
        log_warning "No images to migrate."
        return 0
    fi
    
    echo
    echo "================================================================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "                    EXECUTING MIGRATION PLAN (DRY-RUN)"
    else
        echo "                       EXECUTING MIGRATION PLAN"
    fi
    echo "================================================================================"
    
    local success_count=0
    local total_count=0
    
    while IFS='|' read -r namespace resource_type resource_name source_image dest_image; do
        ((total_count++))
        
        if [[ "$INTERACTIVE" == "true" ]]; then
            echo
            read -p "Migrate $resource_type/$resource_name in $namespace? (y/n/q): " -n 1 -r
            echo
            case $REPLY in
                [Yy])
                    ;;
                [Qq])
                    log_info "Migration cancelled by user."
                    break
                    ;;
                *)
                    log_info "Skipping..."
                    continue
                    ;;
            esac
        fi
        
        if migrate_image "$namespace" "$resource_type" "$resource_name" "$source_image" "$dest_image"; then
            ((success_count++))
        fi
        
    done < "$images_file"
    
    echo
    echo "================================================================================"
    local plan_or_execution="plan"
    if [[ "$DRY_RUN" != "true" ]]; then
        plan_or_execution="execution"
    fi
    echo "Migration $plan_or_execution completed: $success_count/$total_count successful"
    echo "================================================================================"
    
    if [[ $success_count -eq $total_count ]]; then
        return 0
    else
        return 1
    fi
}

# Main function
main() {
    parse_args "$@"
    
    log_info "Kubernetes Image Migration Tool"
    log_info "Source Registry: $SOURCE_REGISTRY"
    log_info "Destination Registry: $DESTINATION_REGISTRY"
    log_info "Namespace: $NAMESPACE"
    log_info "Image Pull Secret: $IMAGE_PULL_SECRET"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: DRY-RUN"
    fi
    
    # Check prerequisites
    check_kubectl
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Please install jq."
        exit 1
    fi
    
    # Scan for images
    local images_file="/tmp/k8s_migration_images_$$.txt"
    scan_cluster > "$images_file"
    
    # Display migration plan
    if ! display_migration_plan "$images_file"; then
        rm -f "$images_file"
        exit 0
    fi
    
    # Save plan to file if requested
    if [[ -n "$OUTPUT_PLAN" ]]; then
        create_json_plan "$images_file" "$OUTPUT_PLAN"
        log_success "Migration plan saved to: $OUTPUT_PLAN"
    fi
    
    # Save CSV plan for auditing if requested
    if [[ -n "$OUTPUT_CSV" ]]; then
        create_csv_plan "$images_file" "$OUTPUT_CSV"
        log_success "Migration audit CSV saved to: $OUTPUT_CSV"
    fi
    
    # Ask for confirmation if not in interactive mode and not dry-run
    if [[ "$INTERACTIVE" != "true" && "$DRY_RUN" != "true" ]]; then
        local image_count
        image_count=$(wc -l < "$images_file")
        echo
        read -p "Proceed with migration of $image_count images? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Migration cancelled."
            rm -f "$images_file"
            exit 0
        fi
    fi
    
    # Execute migration
    if execute_migration "$images_file"; then
        # Create automatic rollback backup if not in dry-run mode
        if [[ "$DRY_RUN" != "true" ]]; then
            local base_name="$NAMESPACE"
            if [[ -n "$OUTPUT_CSV" ]]; then
                base_name=$(basename "$OUTPUT_CSV" .csv)
            fi
            create_rollback_backup "$images_file" "$base_name"
        fi
        
        log_success "Migration completed successfully!"
        rm -f "$images_file"
        exit 0
    else
        log_error "Migration completed with errors."
        rm -f "$images_file"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
