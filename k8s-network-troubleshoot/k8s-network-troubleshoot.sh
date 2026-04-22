#!/bin/bash

# Kubernetes Network Troubleshooting Script
# This script deploys netshoot pods on nodes and verifies network connectivity
# for master-to-master and worker-to-master communication

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default Kubernetes ports to test
ETCD_PORTS=(2379 2380)
API_SERVER_PORTS=(6443)
KUBELET_PORTS=(10250)
KUBE_SCHEDULER_PORTS=(10259)
KUBE_CONTROLLER_PORTS=(10257)
WORKER_PORTS=(30000-32767) # NodePort range

# CNI-specific ports and configurations
# Using a simple approach that works with older bash versions
get_cni_ports() {
    local cni_type=$1
    case "$cni_type" in
        "calico") echo "179 4789" ;;          # BGP, VXLAN
        "flannel") echo "8472 8285" ;;        # VXLAN, UDP backend
        "weave") echo "6783 6784" ;;          # Control, Data plane
        "cilium") echo "4240 8472" ;;         # Health, VXLAN
        "kindnet") echo "10250" ;;            # Uses kubelet for IPAM
        "canal") echo "179 8472" ;;           # Calico + Flannel (BGP + VXLAN)
        "antrea") echo "10349 10350" ;;       # Agent, Controller
        *) echo "" ;;
    esac
}

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

# Function to show help message
show_help() {
    cat << EOF
Kubernetes Network Troubleshooting Script

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Comprehensive network troubleshooting for Kubernetes clusters including:
    - Basic connectivity tests between nodes
    - Packet drop and network stability analysis
    - CNI-specific port testing
    - DNS resolution validation
    - AWS EKS API endpoint connectivity (for EKS clusters)

OPTIONS:
    General Options:
        -h, --help              Show this help message
        --skip-cleanup          Don't cleanup netshoot pods after testing
        --report               Generate a detailed network troubleshooting report

    Test Selection:
        --basic-only           Run only basic ping connectivity tests
        --quick                Quick mode (basic + CNI + DNS, skip intensive tests)
        --connectivity-only    Run connectivity tests (basic + CNI + DNS, no cloud/Nirmata)
        --aws-only            Run only AWS EKS API endpoint tests
        --azure-only          Run only Azure AKS API endpoint tests  
        --cloud-only          Run only cloud provider tests (AWS + Azure)
        --nirmata-only        Run only Nirmata base cluster connectivity tests
        --proxy-only          Run only proxy configuration and routing tests
        --packet-drops-only   Run basic connectivity + packet drop tests only
        --stability-only      Run basic connectivity + network stability tests only

    Test Exclusions:
        --no-packet-drops     Skip packet drop detection tests
        --no-stability        Skip network stability tests
        --no-cni             Skip CNI-specific port testing
        --no-dns             Skip DNS resolution tests
        --no-aws             Skip AWS EKS API endpoint tests
        --no-azure           Skip Azure AKS API endpoint tests
        --no-nirmata         Skip Nirmata base cluster connectivity tests
        --no-proxy           Skip proxy configuration tests

    Nirmata Options:
        --nirmata-endpoint <hostname>  Specify Nirmata base cluster endpoint
                                      (can also use NIRMATA_URL environment variable)

    Proxy Options:
        --proxy-test-endpoint <hostname>  Specify endpoint for proxy testing
                                         (default: httpbin.org)

EXAMPLES:
    # Full comprehensive test (default)
    $0

    # Quick connectivity check
    $0 --quick

    # Basic connectivity only
    $0 --basic-only

    # Skip intensive tests
    $0 --no-packet-drops --no-stability

    # EKS-specific testing only
    $0 --aws-only

    # Test packet drops without other checks
    $0 --packet-drops-only

    # Generate report and keep pods for manual investigation
    $0 --report --skip-cleanup

TEST CATEGORIES:
    Basic Tests:       Ping connectivity between nodes
    Packet Drops:      Intermittent packet loss detection (50 pings)
    Stability:         Network stability over time (20s continuous)
    CNI Tests:         CNI-specific port connectivity (auto-detected)
    DNS Tests:         Kubernetes DNS resolution validation
    AWS Tests:         EKS API endpoints (EKS clusters only)

SUPPORTED PLATFORMS:
    - kind (local development)
    - Amazon EKS
    - Google GKE  
    - Azure AKS
    - Self-managed clusters

SUPPORTED CNI:
    - Calico, Flannel, Weave, Cilium, Canal, Antrea, Kindnet

For more information and troubleshooting guides, visit:
https://kubernetes.io/docs/tasks/debug-application-cluster/debug-cluster/
EOF
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_status "ERROR" "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_status "ERROR" "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_status "SUCCESS" "kubectl is available and connected to cluster"
}

# Function to get node information
get_nodes() {
    local node_type=$1
    if [ "$node_type" = "worker" ]; then
        # For GKE, all visible nodes are workers
        kubectl get nodes -o json | jq -r '.items[] | .metadata.name'
    else
        kubectl get nodes -o json | jq -r ".items[] | select(.metadata.labels[\"node-role.kubernetes.io/$node_type\"] // .metadata.labels[\"kubernetes.io/role\"] == \"$node_type\") | .metadata.name"
    fi
}

# Function to get node IP
get_node_ip() {
    local node_name=$1
    kubectl get node "$node_name" -o json | jq -r '.status.addresses[] | select(.type=="InternalIP") | .address'
}

# Function to deploy netshoot pod on a specific node
deploy_netshoot() {
    local node_name=$1
    local pod_name="netshoot-$node_name"
    
    print_status "INFO" "Deploying netshoot pod on node: $node_name"
    
    # Create temporary pod manifest
    local temp_manifest="/tmp/netshoot-${node_name}.yaml"
    sed "s/TARGET_NODE/$node_name/g; s/netshoot-troubleshoot/$pod_name/g" "$(dirname "$0")/netshoot-pod.yaml" > "$temp_manifest"
    
    # Deploy the pod
    kubectl apply -f "$temp_manifest" || {
        print_status "ERROR" "Failed to deploy netshoot pod on $node_name"
        return 1
    }
    
    # Wait for pod to be ready
    print_status "INFO" "Waiting for pod $pod_name to be ready..."
    kubectl wait --for=condition=Ready pod/"$pod_name" --timeout=120s || {
        print_status "ERROR" "Pod $pod_name failed to become ready"
        kubectl describe pod "$pod_name"
        return 1
    }
    
    print_status "SUCCESS" "Netshoot pod $pod_name is ready on node $node_name"
    rm -f "$temp_manifest"
}

# Function to test port connectivity
test_port_connectivity() {
    local source_pod=$1
    local target_ip=$2
    local port=$3
    local timeout=${4:-5}
    
    local result
    result=$(kubectl exec "$source_pod" -- timeout "$timeout" nc -zv "$target_ip" "$port" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to test for packet drops using ping
test_packet_drops() {
    local source_pod=$1
    local target_ip=$2
    local target_node=$3
    local ping_count=${4:-100}
    local ping_interval=${5:-0.1}
    
    print_status "INFO" "Testing for packet drops from $source_pod to $target_node ($target_ip)"
    print_status "INFO" "Sending $ping_count packets with ${ping_interval}s interval..."
    
    local ping_output
    ping_output=$(kubectl exec "$source_pod" -- ping -c "$ping_count" -i "$ping_interval" -W 2 "$target_ip" 2>&1)
    local ping_exit_code=$?
    
    if [ $ping_exit_code -eq 0 ]; then
        # Parse ping statistics
        local transmitted=$(echo "$ping_output" | grep "packets transmitted" | awk '{print $1}')
        local received=$(echo "$ping_output" | grep "packets transmitted" | awk '{print $4}')
        local loss_percentage=$(echo "$ping_output" | grep "packet loss" | awk '{print $6}' | sed 's/%//')
        local avg_rtt=$(echo "$ping_output" | grep "rtt min/avg/max" | awk -F'/' '{print $5}')
        local max_rtt=$(echo "$ping_output" | grep "rtt min/avg/max" | awk -F'/' '{print $6}')
        local min_rtt=$(echo "$ping_output" | grep "rtt min/avg/max" | awk -F'/' '{print $4}')
        
        if [ -n "$loss_percentage" ] && [ -n "$transmitted" ] && [ -n "$received" ]; then
            if (( $(echo "$loss_percentage == 0" | bc -l) )); then
                print_status "SUCCESS" "No packet loss detected ($transmitted transmitted, $received received, 0% loss)"
            elif (( $(echo "$loss_percentage <= 1" | bc -l) )); then
                print_status "WARNING" "Minor packet loss detected ($transmitted transmitted, $received received, ${loss_percentage}% loss)"
            else
                print_status "WARNING" "Significant packet loss detected ($transmitted transmitted, $received received, ${loss_percentage}% loss)"
            fi
            
            if [ -n "$avg_rtt" ] && [ -n "$min_rtt" ] && [ -n "$max_rtt" ]; then
                print_status "INFO" "RTT stats - Min: ${min_rtt}ms, Avg: ${avg_rtt}ms, Max: ${max_rtt}ms"
                
                # Check for high latency variation (jitter)
                local rtt_diff=$(echo "$max_rtt - $min_rtt" | bc -l 2>/dev/null || echo "0")
                if [ -n "$rtt_diff" ] && (( $(echo "$rtt_diff > 50" | bc -l 2>/dev/null || echo 0) )); then
                    print_status "WARNING" "High jitter detected (${rtt_diff}ms variation) - may indicate network instability"
                fi
            fi
        else
            print_status "WARNING" "Could not parse ping statistics properly"
        fi
    else
        print_status "ERROR" "Ping test failed completely - $target_ip unreachable"
        return 1
    fi
}

# Function to test sustained throughput and detect intermittent issues
test_network_stability() {
    local source_pod=$1
    local target_ip=$2
    local target_node=$3
    local duration=${4:-30}
    
    print_status "INFO" "Testing network stability from $source_pod to $target_node ($target_ip) for ${duration}s"
    
    # Test 1: Continuous ping for detecting intermittent drops
    local ping_output
    ping_output=$(kubectl exec "$source_pod" -- timeout "$duration" ping -i 0.2 "$target_ip" 2>&1)
    local ping_lines=$(echo "$ping_output" | wc -l)
    
    if [ "$ping_lines" -gt 10 ]; then
        local successful_pings=$(echo "$ping_output" | grep "bytes from" | wc -l)
        local timeout_pings=$(echo "$ping_output" | grep -E "(timeout|no answer)" | wc -l)
        local total_attempts=$((successful_pings + timeout_pings))
        
        if [ "$total_attempts" -gt 0 ]; then
            local success_rate=$(echo "scale=2; $successful_pings * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
            print_status "INFO" "Stability test: $successful_pings/$total_attempts successful (${success_rate}%)"
            
            if (( $(echo "$success_rate >= 99" | bc -l 2>/dev/null || echo 0) )); then
                print_status "SUCCESS" "Network connection is stable"
            elif (( $(echo "$success_rate >= 95" | bc -l 2>/dev/null || echo 0) )); then
                print_status "WARNING" "Minor intermittent connectivity issues detected"
            else
                print_status "ERROR" "Significant intermittent connectivity issues detected"
            fi
        fi
    fi
    
    # Test 2: TCP connection stability test (if netcat supports it)
    print_status "INFO" "Testing TCP connection stability..."
    local tcp_test_result
    tcp_test_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "
        for i in \$(seq 1 20); do 
            if nc -z -w 1 '$target_ip' 22 2>/dev/null || nc -z -w 1 '$target_ip' 443 2>/dev/null || nc -z -w 1 '$target_ip' 80 2>/dev/null; then 
                echo 'success'; 
            else 
                echo 'fail'; 
            fi; 
            sleep 0.5; 
        done
    " 2>/dev/null || echo "tcp_test_failed")
    
    if [ "$tcp_test_result" != "tcp_test_failed" ] && [ -n "$tcp_test_result" ]; then
        local tcp_success=$(echo "$tcp_test_result" | grep "success" | wc -l)
        local tcp_total=$(echo "$tcp_test_result" | wc -l)
        if [ "$tcp_total" -gt 0 ]; then
            local tcp_success_rate=$(echo "scale=2; $tcp_success * 100 / $tcp_total" | bc -l 2>/dev/null || echo "0")
            print_status "INFO" "TCP stability test: $tcp_success/$tcp_total connections successful (${tcp_success_rate}%)"
        fi
    else
        print_status "INFO" "TCP stability test skipped (no accessible ports found)"
    fi
}

# Function to detect CNI from cluster
detect_cni() {
    local cni_type=""
    
    # Check for common CNI pods/daemonsets
    if kubectl get pods -n kube-system -o name 2>/dev/null | grep -q flannel; then
        cni_type="flannel"
    elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q calico; then
        cni_type="calico"
    elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q weave; then
        cni_type="weave"
    elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q cilium; then
        cni_type="cilium"
    elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q canal; then
        cni_type="canal"
    elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q antrea; then
        cni_type="antrea"
    elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q kindnet; then
        cni_type="kindnet"
    else
        cni_type="unknown"
    fi
    
    echo "$cni_type"
}

# Function to test multiple ports
test_ports() {
    local source_pod=$1
    local target_node=$2
    local target_ip=$3
    local ports_array=("$@")
    local ports=("${ports_array[@]:3}")
    
    print_status "INFO" "Testing connectivity from $source_pod to $target_node ($target_ip)"
    
    local success_count=0
    local total_count=${#ports[@]}
    
    for port in "${ports[@]}"; do
        if [[ "$port" == *"-"* ]]; then
            # Port range - test a few sample ports
            local start_port=$(echo "$port" | cut -d'-' -f1)
            local end_port=$(echo "$port" | cut -d'-' -f2)
            local sample_ports=($start_port $(($start_port + 100)) $(($start_port + 500)) $end_port)
            
            for sample_port in "${sample_ports[@]}"; do
                if [ "$sample_port" -le "$end_port" ]; then
                    if test_port_connectivity "$source_pod" "$target_ip" "$sample_port" 2; then
                        print_status "SUCCESS" "Port $sample_port (from range $port) is accessible"
                        ((success_count++))
                        break
                    fi
                fi
            done
        else
            if test_port_connectivity "$source_pod" "$target_ip" "$port"; then
                print_status "SUCCESS" "Port $port is accessible"
                ((success_count++))
            else
                print_status "WARNING" "Port $port is not accessible or service not running"
            fi
        fi
    done
    
    print_status "INFO" "Connectivity test summary: $success_count successful connections"
}

# Function to test CNI-specific ports
test_cni_ports() {
    local source_pod=$1
    local target_node=$2
    local target_ip=$3
    local cni_type=$4
    
    if [ "$cni_type" = "unknown" ]; then
        print_status "INFO" "Testing common CNI ports (CNI type unknown)"
        # Test all common ports when CNI is unknown
        local all_ports="179 4789 8472 8285 6783 6784 4240 10349 10350"
        test_ports "$source_pod" "$target_node" "$target_ip" $all_ports
    else
        local cni_ports_str="${CNI_PORTS[$cni_type]}"
        if [ -n "$cni_ports_str" ]; then
            print_status "INFO" "Testing $cni_type CNI ports: $cni_ports_str"
            local cni_ports=($cni_ports_str)
            test_ports "$source_pod" "$target_node" "$target_ip" "${cni_ports[@]}"
        else
            print_status "WARNING" "No specific ports defined for CNI type: $cni_type"
        fi
    fi
}

# Function to detect if running on EKS
is_eks_cluster() {
    # Check for EKS-specific indicators
    if kubectl get nodes -o json | jq -r '.items[0].spec.providerID' | grep -q "aws://"; then
        return 0
    elif kubectl get configmap -n kube-system aws-auth &>/dev/null; then
        return 0
    elif kubectl version --short 2>/dev/null | grep -q "eks.amazonaws.com"; then
        return 0
    else
        return 1
    fi
}

# Function to detect if running on AKS
is_aks_cluster() {
    # Check for AKS-specific indicators
    if kubectl get nodes -o json | jq -r '.items[0].spec.providerID' | grep -q "azure://"; then
        return 0
    elif kubectl get configmap -n kube-system extension-apiserver-authentication &>/dev/null; then
        # Additional check for AKS-specific resources
        if kubectl get nodes -o json | jq -r '.items[0].metadata.labels["kubernetes.azure.com/node-image-version"]' 2>/dev/null | grep -q "AKS"; then
            return 0
        fi
    elif kubectl version --short 2>/dev/null | grep -q "aks"; then
        return 0
    else
        return 1
    fi
}

# Function to get AWS region from cluster
get_aws_region() {
    # Try to get region from node metadata
    local region=""
    
    # Method 1: From node providerID
    region=$(kubectl get nodes -o json | jq -r '.items[0].spec.providerID' | grep -oE '[a-z]{2}-[a-z]+-[0-9]{1}' | head -1)
    
    if [ -z "$region" ]; then
        # Method 2: From AWS CLI config (if available)
        if command -v aws &> /dev/null; then
            region=$(aws configure get region 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$region" ]; then
        # Method 3: Default to us-east-1 if unable to detect
        region="us-east-1"
    fi
    
    echo "$region"
}

# Function to get Azure region from cluster
get_azure_region() {
    # Try to get region from node metadata
    local region=""
    
    # Method 1: From node providerID (format: azure:///subscriptions/.../resourceGroups/.../providers/Microsoft.Compute/virtualMachines/...)
    local provider_id=$(kubectl get nodes -o json | jq -r '.items[0].spec.providerID' 2>/dev/null)
    if [[ "$provider_id" == azure://* ]]; then
        # Extract region from node labels
        region=$(kubectl get nodes -o json | jq -r '.items[0].metadata.labels["topology.kubernetes.io/region"]' 2>/dev/null)
        
        # Fallback to failure-domain label (older AKS versions)
        if [ -z "$region" ] || [ "$region" = "null" ]; then
            region=$(kubectl get nodes -o json | jq -r '.items[0].metadata.labels["failure-domain.beta.kubernetes.io/region"]' 2>/dev/null)
        fi
    fi
    
    if [ -z "$region" ] || [ "$region" = "null" ]; then
        # Method 2: From Azure CLI config (if available)
        if command -v az &> /dev/null; then
            region=$(az account list-locations --query "[?isDefault].name" -o tsv 2>/dev/null | head -1)
        fi
    fi
    
    if [ -z "$region" ] || [ "$region" = "null" ]; then
        # Method 3: Default to eastus if unable to detect
        region="eastus"
    fi
    
    echo "$region"
}

# Function to test AWS API endpoints connectivity for EKS
test_aws_api_connectivity() {
    local source_pod=$1
    local aws_region=${2:-$(get_aws_region)}
    
    print_status "INFO" "Testing AWS API endpoint connectivity for EKS (region: $aws_region)"
    
    # AWS API endpoints critical for EKS
    local -A aws_endpoints=(
        ["EKS"]="eks.$aws_region.amazonaws.com:443"
        ["EC2"]="ec2.$aws_region.amazonaws.com:443"
        ["IAM"]="iam.amazonaws.com:443"
        ["STS"]="sts.$aws_region.amazonaws.com:443"
        ["ECR"]="ecr.$aws_region.amazonaws.com:443"
        ["ELB"]="elasticloadbalancing.$aws_region.amazonaws.com:443"
        ["CloudFormation"]="cloudformation.$aws_region.amazonaws.com:443"
        ["AutoScaling"]="autoscaling.$aws_region.amazonaws.com:443"
    )
    
    local success_count=0
    local total_endpoints=${#aws_endpoints[@]}
    
    for service in "${!aws_endpoints[@]}"; do
        local endpoint="${aws_endpoints[$service]}"
        local hostname=$(echo "$endpoint" | cut -d':' -f1)
        local port=$(echo "$endpoint" | cut -d':' -f2)
        
        print_status "INFO" "Testing $service API endpoint: $hostname:$port"
        
        # Test DNS resolution first
        if kubectl exec "$source_pod" -- nslookup "$hostname" &> /dev/null; then
            print_status "SUCCESS" "$service DNS resolution successful"
            
            # Test HTTPS connectivity
            if test_port_connectivity "$source_pod" "$hostname" "$port" 10; then
                print_status "SUCCESS" "$service API endpoint ($hostname:$port) is accessible"
                ((success_count++))
                
                # Test HTTPS handshake
                local ssl_test
                ssl_test=$(kubectl exec "$source_pod" -- timeout 10 openssl s_client -connect "$hostname:$port" -servername "$hostname" </dev/null 2>&1 | grep "Verify return code")
                if echo "$ssl_test" | grep -q "0 (ok)"; then
                    print_status "SUCCESS" "$service SSL/TLS handshake successful"
                elif [ -n "$ssl_test" ]; then
                    print_status "WARNING" "$service SSL/TLS verification: $(echo "$ssl_test" | sed 's/.*Verify return code: //')"
                fi
            else
                print_status "ERROR" "$service API endpoint ($hostname:$port) is not accessible"
            fi
        else
            print_status "ERROR" "$service DNS resolution failed for $hostname"
        fi
        
        echo ""
    done
    
    # Test AWS metadata service (for nodes)
    print_status "INFO" "Testing AWS EC2 metadata service connectivity"
    if kubectl exec "$source_pod" -- timeout 5 curl -s http://169.254.169.254/latest/meta-data/instance-id &> /dev/null; then
        print_status "SUCCESS" "AWS metadata service is accessible"
    else
        print_status "WARNING" "AWS metadata service not accessible (expected if not on EC2 instance)"
    fi
    
    # Summary
    local success_percentage=$(echo "scale=2; $success_count * 100 / $total_endpoints" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "AWS API connectivity summary: $success_count/$total_endpoints endpoints accessible (${success_percentage}%)"
    
    if (( $(echo "$success_percentage >= 90" | bc -l 2>/dev/null || echo 0) )); then
        print_status "SUCCESS" "AWS API connectivity is healthy for EKS operations"
    elif (( $(echo "$success_percentage >= 70" | bc -l 2>/dev/null || echo 0) )); then
        print_status "WARNING" "Some AWS API endpoints are not accessible - may impact some EKS features"
    else
        print_status "ERROR" "Significant AWS API connectivity issues detected - EKS operations may be impaired"
    fi
}

# Function to test Azure API endpoints connectivity for AKS
test_azure_api_connectivity() {
    local source_pod=$1
    local azure_region=${2:-$(get_azure_region)}
    
    print_status "INFO" "Testing Azure API endpoint connectivity for AKS (region: $azure_region)"
    
    # Azure API endpoints critical for AKS
    local -A azure_endpoints=(
        ["AKS"]="management.azure.com:443"
        ["Resource Manager"]="management.azure.com:443"
        ["Azure AD"]="login.microsoftonline.com:443"
        ["Container Registry"]="$azure_region.azurecr.io:443"
        ["Storage"]="$azure_region.blob.core.windows.net:443"
        ["Key Vault"]="$azure_region.vault.azure.net:443"
        ["Monitor"]="$azure_region.monitoring.azure.com:443"
        ["Network"]="management.azure.com:443"
        ["Compute"]="management.azure.com:443"
    )
    
    local success_count=0
    local total_endpoints=${#azure_endpoints[@]}
    
    for service in "${!azure_endpoints[@]}"; do
        local endpoint="${azure_endpoints[$service]}"
        local hostname=$(echo "$endpoint" | cut -d':' -f1)
        local port=$(echo "$endpoint" | cut -d':' -f2)
        
        print_status "INFO" "Testing $service API endpoint: $hostname:$port"
        
        # Test DNS resolution first
        if kubectl exec "$source_pod" -- nslookup "$hostname" &> /dev/null; then
            print_status "SUCCESS" "$service DNS resolution successful"
            
            # Test HTTPS connectivity
            if test_port_connectivity "$source_pod" "$hostname" "$port" 10; then
                print_status "SUCCESS" "$service API endpoint ($hostname:$port) is accessible"
                ((success_count++))
                
                # Test HTTPS handshake
                local ssl_test
                ssl_test=$(kubectl exec "$source_pod" -- timeout 10 openssl s_client -connect "$hostname:$port" -servername "$hostname" </dev/null 2>&1 | grep "Verify return code")
                if echo "$ssl_test" | grep -q "0 (ok)"; then
                    print_status "SUCCESS" "$service SSL/TLS handshake successful"
                elif [ -n "$ssl_test" ]; then
                    print_status "WARNING" "$service SSL/TLS verification: $(echo "$ssl_test" | sed 's/.*Verify return code: //')"
                fi
            else
                print_status "ERROR" "$service API endpoint ($hostname:$port) is not accessible"
            fi
        else
            print_status "ERROR" "$service DNS resolution failed for $hostname"
        fi
        
        echo ""
    done
    
    # Test Azure metadata service (for nodes)
    print_status "INFO" "Testing Azure Instance Metadata Service connectivity"
    if kubectl exec "$source_pod" -- timeout 5 curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/azEnvironment?api-version=2018-10-01&format=text" &> /dev/null; then
        print_status "SUCCESS" "Azure metadata service is accessible"
    else
        print_status "WARNING" "Azure metadata service not accessible (expected if not on Azure VM)"
    fi
    
    # Summary
    local success_percentage=$(echo "scale=2; $success_count * 100 / $total_endpoints" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Azure API connectivity summary: $success_count/$total_endpoints endpoints accessible (${success_percentage}%)"
    
    if (( $(echo "$success_percentage >= 90" | bc -l 2>/dev/null || echo 0) )); then
        print_status "SUCCESS" "Azure API connectivity is healthy for AKS operations"
    elif (( $(echo "$success_percentage >= 70" | bc -l 2>/dev/null || echo 0) )); then
        print_status "WARNING" "Some Azure API endpoints are not accessible - may impact some AKS features"
    else
        print_status "ERROR" "Significant Azure API connectivity issues detected - AKS operations may be impaired"
    fi
}

# Function to test EKS-specific networking requirements
test_eks_networking() {
    local source_pod=$1
    
    print_status "INFO" "=========================================="
    print_status "INFO" "EKS-SPECIFIC NETWORKING TESTS"
    print_status "INFO" "=========================================="
    
    local aws_region=$(get_aws_region)
    print_status "INFO" "Detected AWS region: $aws_region"
    
    # Test AWS API endpoints
    test_aws_api_connectivity "$source_pod" "$aws_region"
    
    echo ""
    
    # Test VPC endpoints (if configured)
    print_status "INFO" "Testing VPC endpoint connectivity..."
    
    # Since we can't know the actual VPC endpoint IDs, we'll test for their DNS patterns
    local vpc_dns_test
    vpc_dns_test=$(kubectl exec "$source_pod" -- nslookup "eks.$aws_region.amazonaws.com" 2>&1)
    
    if echo "$vpc_dns_test" | grep -q "vpce-"; then
        print_status "SUCCESS" "VPC endpoints detected for EKS service"
    else
        print_status "INFO" "No VPC endpoints detected - using public AWS API endpoints"
    fi
    
    # Test container registry access
    print_status "INFO" "Testing container registry connectivity..."
    local ecr_endpoint="$aws_region.amazonaws.com"
    if kubectl exec "$source_pod" -- nslookup "$ecr_endpoint" &> /dev/null; then
        print_status "SUCCESS" "ECR public endpoint DNS resolution successful"
    fi
    
    # Test Docker Hub (fallback registry)
    if kubectl exec "$source_pod" -- nslookup "registry-1.docker.io" &> /dev/null; then
        print_status "SUCCESS" "Docker Hub registry DNS resolution successful"
        if test_port_connectivity "$source_pod" "registry-1.docker.io" "443" 10; then
            print_status "SUCCESS" "Docker Hub registry is accessible"
        fi
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect proxy configuration from cluster
detect_proxy_config() {
    local proxy_detected=false
    local proxy_info=""
    
    # Method 1: Check environment variables in kube-system pods
    local proxy_vars
    proxy_vars=$(kubectl get pods -n kube-system -o json 2>/dev/null | jq -r '.items[].spec.containers[].env[]? | select(.name | test("PROXY|proxy")) | .name + "=" + .value' 2>/dev/null | head -5)
    
    if [ -n "$proxy_vars" ]; then
        proxy_detected=true
        proxy_info="Environment variables: $(echo "$proxy_vars" | tr '\n' ' ')"
    fi
    
    # Method 2: Check ConfigMaps for proxy configuration
    local proxy_configmaps
    proxy_configmaps=$(kubectl get configmaps -A -o json 2>/dev/null | jq -r '.items[] | select(.data | keys[] | test("proxy|PROXY")) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | head -3)
    
    if [ -n "$proxy_configmaps" ] && [ "$proxy_detected" = false ]; then
        proxy_detected=true
        proxy_info="ConfigMaps: $proxy_configmaps"
    fi
    
    # Method 3: Check for common proxy settings in node configuration
    local node_proxy
    node_proxy=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' 2>/dev/null | grep -i proxy || echo "")
    
    echo "$proxy_detected|$proxy_info"
}

# Function to test proxy configuration and routing
test_proxy_configuration() {
    local source_pod=$1
    local test_endpoint=${2:-"httpbin.org"}
    
    print_status "INFO" "=========================================="
    print_status "INFO" "PROXY CONFIGURATION TESTS"
    print_status "INFO" "=========================================="
    
    # Detect existing proxy configuration
    local proxy_detection
    proxy_detection=$(detect_proxy_config)
    local proxy_detected=$(echo "$proxy_detection" | cut -d'|' -f1)
    local proxy_info=$(echo "$proxy_detection" | cut -d'|' -f2)
    
    if [ "$proxy_detected" = "true" ]; then
        print_status "INFO" "Proxy configuration detected in cluster: $proxy_info"
    else
        print_status "INFO" "No explicit proxy configuration detected in cluster"
    fi
    
    # Test direct connection first
    print_status "INFO" "Testing direct connection to $test_endpoint"
    local direct_test
    direct_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$test_endpoint" 2>&1)
    
    if echo "$direct_test" | grep -q "HTTP/[12]"; then
        print_status "SUCCESS" "Direct HTTPS connection to $test_endpoint successful"
    else
        print_status "WARNING" "Direct HTTPS connection to $test_endpoint failed"
    fi
    
    # Test with trace to check routing path
    print_status "INFO" "Performing connection trace analysis..."
    
    # Method 1: Check for proxy headers in response
    local proxy_headers
    proxy_headers=$(kubectl exec "$source_pod" -- timeout 15 curl -v "https://$test_endpoint/headers" 2>&1 | grep -i "proxy\|x-forwarded\|via:" || echo "")
    
    if [ -n "$proxy_headers" ]; then
        print_status "SUCCESS" "Proxy headers detected in response - traffic appears to be routed through proxy"
        print_status "INFO" "Proxy evidence: $(echo "$proxy_headers" | head -2 | tr '\n' ' ')"
    fi
    
    # Method 2: DNS resolution analysis for proxy detection
    print_status "INFO" "Analyzing DNS resolution patterns..."
    local dns_trace
    dns_trace=$(kubectl exec "$source_pod" -- nslookup "$test_endpoint" 2>&1)
    
    # Look for proxy-related hostnames in DNS responses
    if echo "$dns_trace" | grep -i "proxy\|gateway\|firewall" | head -3; then
        print_status "SUCCESS" "Proxy-related hostnames detected in DNS resolution"
    else
        print_status "INFO" "No proxy-related hostnames found in DNS resolution"
    fi
    
    # Method 3: Traceroute analysis (if available)
    print_status "INFO" "Testing network path analysis..."
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 20 traceroute "$test_endpoint" 2>&1 | head -10 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for proxy-related hops in traceroute
        local proxy_hops
        proxy_hops=$(echo "$traceroute_output" | grep -i "proxy\|gateway\|firewall" || echo "")
        
        if [ -n "$proxy_hops" ]; then
            print_status "SUCCESS" "Proxy/gateway hops detected in network path"
            print_status "INFO" "Proxy path: $(echo "$proxy_hops" | head -2 | tr '\n' ' ')"
        else
            print_status "INFO" "No obvious proxy hops detected in traceroute"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Method 4: Environment variable check inside test pod
    print_status "INFO" "Checking proxy environment variables in pod..."
    local pod_proxy_vars
    pod_proxy_vars=$(kubectl exec "$source_pod" -- env | grep -i "proxy\|http_proxy\|https_proxy\|no_proxy" || echo "")
    
    if [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy environment variables found in pod:"
        echo "$pod_proxy_vars" | while read -r var; do
            print_status "INFO" "  $var"
        done
    else
        print_status "INFO" "No proxy environment variables found in pod"
    fi
    
    # Method 5: Connection timing analysis (proxy typically adds latency)
    print_status "INFO" "Analyzing connection timing for proxy detection..."
    local timing_test
    timing_test=$(kubectl exec "$source_pod" -- timeout 15 curl -w "connect:%{time_connect},total:%{time_total}" -s -o /dev/null "https://$test_endpoint" 2>/dev/null || echo "timing_failed")
    
    if [ "$timing_test" != "timing_failed" ]; then
        local connect_time=$(echo "$timing_test" | sed 's/.*connect:\([^,]*\).*/\1/')
        local total_time=$(echo "$timing_test" | sed 's/.*total:\([^,]*\).*/\1/')
        
        print_status "INFO" "Connection timing - Connect: ${connect_time}s, Total: ${total_time}s"
        
        # Proxy connections typically have higher connect times
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$connect_time > 0.5" | bc -l 2>/dev/null || echo 0) )); then
                print_status "INFO" "Higher connect time may indicate proxy routing"
            fi
        fi
    fi
    
    # Method 6: Test multiple endpoints to confirm proxy behavior
    print_status "INFO" "Testing multiple endpoints for consistent proxy behavior..."
    local test_endpoints=("google.com" "github.com" "$test_endpoint")
    local proxy_consistent=0
    local total_tests=0
    
    for endpoint in "${test_endpoints[@]}"; do
        local endpoint_test
        endpoint_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$endpoint" 2>&1)
        
        if echo "$endpoint_test" | grep -q "HTTP/[12]"; then
            ((total_tests++))
            # Check if response shows proxy characteristics
            if echo "$endpoint_test" | grep -qi "proxy\|via:\|x-forwarded"; then
                ((proxy_consistent++))
            fi
        fi
    done
    
    if [ $total_tests -gt 0 ] && [ $proxy_consistent -gt 0 ]; then
        local proxy_percentage=$(echo "scale=0; $proxy_consistent * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
        print_status "INFO" "Proxy indicators found in $proxy_consistent/$total_tests endpoint tests (${proxy_percentage}%)"
        
        if [ $proxy_consistent -eq $total_tests ]; then
            print_status "SUCCESS" "Consistent proxy behavior detected across all test endpoints"
        elif [ $proxy_consistent -gt 0 ]; then
            print_status "WARNING" "Inconsistent proxy behavior - some traffic may bypass proxy"
        fi
    fi
    
    # Summary
    print_status "INFO" "Proxy configuration summary:"
    if [ "$proxy_detected" = "true" ] || [ -n "$proxy_headers" ] || [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy configuration appears to be active and functioning"
    else
        print_status "INFO" "No clear evidence of proxy configuration - traffic appears to be direct"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect Nirmata cluster by checking for Nirmata components
is_nirmata_cluster() {
    # Check for Nirmata-specific resources
    if kubectl get pods -n nirmata-system &>/dev/null; then
        return 0
    elif kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | grep -q nirmata; then
        return 0
    elif kubectl get configmap -A 2>/dev/null | grep -q nirmata; then
        return 0
    else
        return 1
    fi
}

# Function to get Nirmata endpoint from cluster or environment
get_nirmata_endpoint() {
    local endpoint=""
    
    # Method 1: From environment variable
    if [ -n "$NIRMATA_URL" ]; then
        endpoint="$NIRMATA_URL"
    elif [ -n "$NIRMATA_ENDPOINT" ]; then
        endpoint="$NIRMATA_ENDPOINT"
    fi
    
    # Method 2: From Nirmata ConfigMap (if available)
    if [ -z "$endpoint" ]; then
        endpoint=$(kubectl get configmap nirmata-config -n nirmata-system -o jsonpath='{.data.nirmata-url}' 2>/dev/null || echo "")
    fi
    
    # Method 3: From Nirmata agent configuration
    if [ -z "$endpoint" ]; then
        endpoint=$(kubectl get secret nirmata-agent-config -n nirmata-system -o jsonpath='{.data.nirmata-url}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    fi
    
    # Clean up the endpoint (remove protocol if present)
    endpoint=$(echo "$endpoint" | sed 's|^https\?://||' | sed 's|/$||')
    
    echo "$endpoint"
}

# Function to test Nirmata base cluster connectivity
test_nirmata_connectivity() {
    local source_pod=$1
    local nirmata_endpoint=${2:-$(get_nirmata_endpoint)}
    
    if [ -z "$nirmata_endpoint" ]; then
        print_status "WARNING" "No Nirmata endpoint provided and unable to auto-detect"
        print_status "INFO" "Use --nirmata-endpoint <hostname> or set NIRMATA_URL environment variable"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "NIRMATA CONNECTIVITY TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing Nirmata base cluster connectivity: $nirmata_endpoint"
    
    # Test DNS resolution first
    if kubectl exec "$source_pod" -- nslookup "$nirmata_endpoint" &> /dev/null; then
        print_status "SUCCESS" "Nirmata endpoint DNS resolution successful"
        
        # Test HTTPS connectivity (port 443)
        if test_port_connectivity "$source_pod" "$nirmata_endpoint" "443" 15; then
            print_status "SUCCESS" "Nirmata endpoint ($nirmata_endpoint:443) is accessible"
            
            # Test HTTPS handshake and certificate validation
            local ssl_test
            ssl_test=$(kubectl exec "$source_pod" -- timeout 15 openssl s_client -connect "$nirmata_endpoint:443" -servername "$nirmata_endpoint" </dev/null 2>&1)
            
            if echo "$ssl_test" | grep -q "Verify return code: 0 (ok)"; then
                print_status "SUCCESS" "Nirmata SSL/TLS certificate is valid"
            elif echo "$ssl_test" | grep -q "Verify return code:"; then
                local verify_code=$(echo "$ssl_test" | grep "Verify return code:" | sed 's/.*Verify return code: //')
                print_status "WARNING" "Nirmata SSL/TLS verification: $verify_code"
            else
                print_status "WARNING" "Unable to verify Nirmata SSL/TLS certificate"
            fi
            
            # Test HTTP response (basic connectivity)
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$nirmata_endpoint" 2>&1)
            
            if echo "$http_test" | grep -q "HTTP/[12]"; then
                local http_status=$(echo "$http_test" | head -1 | awk '{print $2}')
                if [[ "$http_status" =~ ^[23] ]]; then
                    print_status "SUCCESS" "Nirmata endpoint HTTP response successful (Status: $http_status)"
                else
                    print_status "WARNING" "Nirmata endpoint responded with HTTP status: $http_status"
                fi
            else
                print_status "WARNING" "Unable to get HTTP response from Nirmata endpoint"
            fi
            
        else
            print_status "ERROR" "Nirmata endpoint ($nirmata_endpoint:443) is not accessible"
        fi
    else
        print_status "ERROR" "Nirmata endpoint DNS resolution failed for $nirmata_endpoint"
    fi
    
    # Test common Nirmata API paths
    print_status "INFO" "Testing Nirmata API endpoints..."
    
    local -a nirmata_paths=(
        "/health"
        "/api/health"
        "/users/api/health"
    )
    
    local api_success=false
    for path in "${nirmata_paths[@]}"; do
        local api_test
        api_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -o /dev/null -w "%{http_code}" "https://$nirmata_endpoint$path" 2>/dev/null || echo "000")
        
        if [[ "$api_test" =~ ^[23] ]]; then
            print_status "SUCCESS" "Nirmata API path $path is accessible (HTTP $api_test)"
            api_success=true
            break
        fi
    done
    
    if [ "$api_success" = false ]; then
        print_status "WARNING" "No Nirmata API health endpoints responded successfully"
    fi
    
    # Check for existing Nirmata components in the cluster
    if is_nirmata_cluster; then
        print_status "SUCCESS" "Nirmata components detected in cluster"
        
        # Show status of Nirmata components
        local nirmata_pods
        nirmata_pods=$(kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | grep nirmata | wc -l)
        if [ "$nirmata_pods" -gt 0 ]; then
            print_status "INFO" "Found $nirmata_pods running Nirmata pods in the cluster"
        fi
    else
        print_status "INFO" "No Nirmata components found in cluster (normal for unmanaged clusters)"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect proxy configuration from cluster
detect_proxy_config() {
    local proxy_detected=false
    local proxy_info=""
    
    # Method 1: Check environment variables in kube-system pods
    local proxy_vars
    proxy_vars=$(kubectl get pods -n kube-system -o json 2>/dev/null | jq -r '.items[].spec.containers[].env[]? | select(.name | test("PROXY|proxy")) | .name + "=" + .value' 2>/dev/null | head -5)
    
    if [ -n "$proxy_vars" ]; then
        proxy_detected=true
        proxy_info="Environment variables: $(echo "$proxy_vars" | tr '\n' ' ')"
    fi
    
    # Method 2: Check ConfigMaps for proxy configuration
    local proxy_configmaps
    proxy_configmaps=$(kubectl get configmaps -A -o json 2>/dev/null | jq -r '.items[] | select(.data | keys[] | test("proxy|PROXY")) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | head -3)
    
    if [ -n "$proxy_configmaps" ] && [ "$proxy_detected" = false ]; then
        proxy_detected=true
        proxy_info="ConfigMaps: $proxy_configmaps"
    fi
    
    # Method 3: Check for common proxy settings in node configuration
    local node_proxy
    node_proxy=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' 2>/dev/null | grep -i proxy || echo "")
    
    echo "$proxy_detected|$proxy_info"
}

# Function to test proxy configuration and routing
test_proxy_configuration() {
    local source_pod=$1
    local test_endpoint=${2:-"httpbin.org"}
    
    print_status "INFO" "=========================================="
    print_status "INFO" "PROXY CONFIGURATION TESTS"
    print_status "INFO" "=========================================="
    
    # Detect existing proxy configuration
    local proxy_detection
    proxy_detection=$(detect_proxy_config)
    local proxy_detected=$(echo "$proxy_detection" | cut -d'|' -f1)
    local proxy_info=$(echo "$proxy_detection" | cut -d'|' -f2)
    
    if [ "$proxy_detected" = "true" ]; then
        print_status "INFO" "Proxy configuration detected in cluster: $proxy_info"
    else
        print_status "INFO" "No explicit proxy configuration detected in cluster"
    fi
    
    # Test direct connection first
    print_status "INFO" "Testing direct connection to $test_endpoint"
    local direct_test
    direct_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$test_endpoint" 2>&1)
    
    if echo "$direct_test" | grep -q "HTTP/[12]"; then
        print_status "SUCCESS" "Direct HTTPS connection to $test_endpoint successful"
    else
        print_status "WARNING" "Direct HTTPS connection to $test_endpoint failed"
    fi
    
    # Test with trace to check routing path
    print_status "INFO" "Performing connection trace analysis..."
    
    # Method 1: Check for proxy headers in response
    local proxy_headers
    proxy_headers=$(kubectl exec "$source_pod" -- timeout 15 curl -v "https://$test_endpoint/headers" 2>&1 | grep -i "proxy\|x-forwarded\|via:" || echo "")
    
    if [ -n "$proxy_headers" ]; then
        print_status "SUCCESS" "Proxy headers detected in response - traffic appears to be routed through proxy"
        print_status "INFO" "Proxy evidence: $(echo "$proxy_headers" | head -2 | tr '\n' ' ')"
    fi
    
    # Method 2: DNS resolution analysis for proxy detection
    print_status "INFO" "Analyzing DNS resolution patterns..."
    local dns_trace
    dns_trace=$(kubectl exec "$source_pod" -- nslookup "$test_endpoint" 2>&1)
    
    # Look for proxy-related hostnames in DNS responses
    if echo "$dns_trace" | grep -i "proxy\|gateway\|firewall" | head -3; then
        print_status "SUCCESS" "Proxy-related hostnames detected in DNS resolution"
    else
        print_status "INFO" "No proxy-related hostnames found in DNS resolution"
    fi
    
    # Method 3: Traceroute analysis (if available)
    print_status "INFO" "Testing network path analysis..."
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 20 traceroute "$test_endpoint" 2>&1 | head -10 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for proxy-related hops in traceroute
        local proxy_hops
        proxy_hops=$(echo "$traceroute_output" | grep -i "proxy\|gateway\|firewall" || echo "")
        
        if [ -n "$proxy_hops" ]; then
            print_status "SUCCESS" "Proxy/gateway hops detected in network path"
            print_status "INFO" "Proxy path: $(echo "$proxy_hops" | head -2 | tr '\n' ' ')"
        else
            print_status "INFO" "No obvious proxy hops detected in traceroute"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Method 4: Environment variable check inside test pod
    print_status "INFO" "Checking proxy environment variables in pod..."
    local pod_proxy_vars
    pod_proxy_vars=$(kubectl exec "$source_pod" -- env | grep -i "proxy\|http_proxy\|https_proxy\|no_proxy" || echo "")
    
    if [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy environment variables found in pod:"
        echo "$pod_proxy_vars" | while read -r var; do
            print_status "INFO" "  $var"
        done
    else
        print_status "INFO" "No proxy environment variables found in pod"
    fi
    
    # Method 5: Connection timing analysis (proxy typically adds latency)
    print_status "INFO" "Analyzing connection timing for proxy detection..."
    local timing_test
    timing_test=$(kubectl exec "$source_pod" -- timeout 15 curl -w "connect:%{time_connect},total:%{time_total}" -s -o /dev/null "https://$test_endpoint" 2>/dev/null || echo "timing_failed")
    
    if [ "$timing_test" != "timing_failed" ]; then
        local connect_time=$(echo "$timing_test" | sed 's/.*connect:\([^,]*\).*/\1/')
        local total_time=$(echo "$timing_test" | sed 's/.*total:\([^,]*\).*/\1/')
        
        print_status "INFO" "Connection timing - Connect: ${connect_time}s, Total: ${total_time}s"
        
        # Proxy connections typically have higher connect times
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$connect_time > 0.5" | bc -l 2>/dev/null || echo 0) )); then
                print_status "INFO" "Higher connect time may indicate proxy routing"
            fi
        fi
    fi
    
    # Method 6: Test multiple endpoints to confirm proxy behavior
    print_status "INFO" "Testing multiple endpoints for consistent proxy behavior..."
    local test_endpoints=("google.com" "github.com" "$test_endpoint")
    local proxy_consistent=0
    local total_tests=0
    
    for endpoint in "${test_endpoints[@]}"; do
        local endpoint_test
        endpoint_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$endpoint" 2>&1)
        
        if echo "$endpoint_test" | grep -q "HTTP/[12]"; then
            ((total_tests++))
            # Check if response shows proxy characteristics
            if echo "$endpoint_test" | grep -qi "proxy\|via:\|x-forwarded"; then
                ((proxy_consistent++))
            fi
        fi
    done
    
    if [ $total_tests -gt 0 ] && [ $proxy_consistent -gt 0 ]; then
        local proxy_percentage=$(echo "scale=0; $proxy_consistent * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
        print_status "INFO" "Proxy indicators found in $proxy_consistent/$total_tests endpoint tests (${proxy_percentage}%)"
        
        if [ $proxy_consistent -eq $total_tests ]; then
            print_status "SUCCESS" "Consistent proxy behavior detected across all test endpoints"
        elif [ $proxy_consistent -gt 0 ]; then
            print_status "WARNING" "Inconsistent proxy behavior - some traffic may bypass proxy"
        fi
    fi
    
    # Summary
    print_status "INFO" "Proxy configuration summary:"
    if [ "$proxy_detected" = "true" ] || [ -n "$proxy_headers" ] || [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy configuration appears to be active and functioning"
    else
        print_status "INFO" "No clear evidence of proxy configuration - traffic appears to be direct"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to test AKS-specific networking requirements
test_aks_networking() {
    local source_pod=$1
    
    print_status "INFO" "=========================================="
    print_status "INFO" "AKS-SPECIFIC NETWORKING TESTS"
    print_status "INFO" "=========================================="
    
    local azure_region=$(get_azure_region)
    print_status "INFO" "Detected Azure region: $azure_region"
    
    # Test Azure API endpoints
    test_azure_api_connectivity "$source_pod" "$azure_region"
    
    echo ""
    
    # Test Azure service endpoints (if configured)
    print_status "INFO" "Testing Azure service endpoint connectivity..."
    
    # Test for private endpoints
    local private_endpoint_test
    private_endpoint_test=$(kubectl exec "$source_pod" -- nslookup "management.azure.com" 2>&1)
    
    if echo "$private_endpoint_test" | grep -q "privatelink"; then
        print_status "SUCCESS" "Private endpoints detected for Azure services"
    else
        print_status "INFO" "No private endpoints detected - using public Azure API endpoints"
    fi
    
    # Test container registry access
    print_status "INFO" "Testing container registry connectivity..."
    
    # Test Azure Container Registry
    local acr_endpoint="$azure_region.azurecr.io"
    if kubectl exec "$source_pod" -- nslookup "$acr_endpoint" &> /dev/null; then
        print_status "SUCCESS" "ACR endpoint DNS resolution successful"
        if test_port_connectivity "$source_pod" "$acr_endpoint" "443" 10; then
            print_status "SUCCESS" "Azure Container Registry is accessible"
        fi
    fi
    
    # Test Microsoft Container Registry (MCR)
    if kubectl exec "$source_pod" -- nslookup "mcr.microsoft.com" &> /dev/null; then
        print_status "SUCCESS" "MCR DNS resolution successful"
        if test_port_connectivity "$source_pod" "mcr.microsoft.com" "443" 10; then
            print_status "SUCCESS" "Microsoft Container Registry is accessible"
        fi
    fi
    
    # Test Docker Hub (fallback registry)
    if kubectl exec "$source_pod" -- nslookup "registry-1.docker.io" &> /dev/null; then
        print_status "SUCCESS" "Docker Hub registry DNS resolution successful"
        if test_port_connectivity "$source_pod" "registry-1.docker.io" "443" 10; then
            print_status "SUCCESS" "Docker Hub registry is accessible"
        fi
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect proxy configuration from cluster
detect_proxy_config() {
    local proxy_detected=false
    local proxy_info=""
    
    # Method 1: Check environment variables in kube-system pods
    local proxy_vars
    proxy_vars=$(kubectl get pods -n kube-system -o json 2>/dev/null | jq -r '.items[].spec.containers[].env[]? | select(.name | test("PROXY|proxy")) | .name + "=" + .value' 2>/dev/null | head -5)
    
    if [ -n "$proxy_vars" ]; then
        proxy_detected=true
        proxy_info="Environment variables: $(echo "$proxy_vars" | tr '\n' ' ')"
    fi
    
    # Method 2: Check ConfigMaps for proxy configuration
    local proxy_configmaps
    proxy_configmaps=$(kubectl get configmaps -A -o json 2>/dev/null | jq -r '.items[] | select(.data | keys[] | test("proxy|PROXY")) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | head -3)
    
    if [ -n "$proxy_configmaps" ] && [ "$proxy_detected" = false ]; then
        proxy_detected=true
        proxy_info="ConfigMaps: $proxy_configmaps"
    fi
    
    # Method 3: Check for common proxy settings in node configuration
    local node_proxy
    node_proxy=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' 2>/dev/null | grep -i proxy || echo "")
    
    echo "$proxy_detected|$proxy_info"
}

# Function to test proxy configuration and routing
test_proxy_configuration() {
    local source_pod=$1
    local test_endpoint=${2:-"httpbin.org"}
    
    print_status "INFO" "=========================================="
    print_status "INFO" "PROXY CONFIGURATION TESTS"
    print_status "INFO" "=========================================="
    
    # Detect existing proxy configuration
    local proxy_detection
    proxy_detection=$(detect_proxy_config)
    local proxy_detected=$(echo "$proxy_detection" | cut -d'|' -f1)
    local proxy_info=$(echo "$proxy_detection" | cut -d'|' -f2)
    
    if [ "$proxy_detected" = "true" ]; then
        print_status "INFO" "Proxy configuration detected in cluster: $proxy_info"
    else
        print_status "INFO" "No explicit proxy configuration detected in cluster"
    fi
    
    # Test direct connection first
    print_status "INFO" "Testing direct connection to $test_endpoint"
    local direct_test
    direct_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$test_endpoint" 2>&1)
    
    if echo "$direct_test" | grep -q "HTTP/[12]"; then
        print_status "SUCCESS" "Direct HTTPS connection to $test_endpoint successful"
    else
        print_status "WARNING" "Direct HTTPS connection to $test_endpoint failed"
    fi
    
    # Test with trace to check routing path
    print_status "INFO" "Performing connection trace analysis..."
    
    # Method 1: Check for proxy headers in response
    local proxy_headers
    proxy_headers=$(kubectl exec "$source_pod" -- timeout 15 curl -v "https://$test_endpoint/headers" 2>&1 | grep -i "proxy\|x-forwarded\|via:" || echo "")
    
    if [ -n "$proxy_headers" ]; then
        print_status "SUCCESS" "Proxy headers detected in response - traffic appears to be routed through proxy"
        print_status "INFO" "Proxy evidence: $(echo "$proxy_headers" | head -2 | tr '\n' ' ')"
    fi
    
    # Method 2: DNS resolution analysis for proxy detection
    print_status "INFO" "Analyzing DNS resolution patterns..."
    local dns_trace
    dns_trace=$(kubectl exec "$source_pod" -- nslookup "$test_endpoint" 2>&1)
    
    # Look for proxy-related hostnames in DNS responses
    if echo "$dns_trace" | grep -i "proxy\|gateway\|firewall" | head -3; then
        print_status "SUCCESS" "Proxy-related hostnames detected in DNS resolution"
    else
        print_status "INFO" "No proxy-related hostnames found in DNS resolution"
    fi
    
    # Method 3: Traceroute analysis (if available)
    print_status "INFO" "Testing network path analysis..."
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 20 traceroute "$test_endpoint" 2>&1 | head -10 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for proxy-related hops in traceroute
        local proxy_hops
        proxy_hops=$(echo "$traceroute_output" | grep -i "proxy\|gateway\|firewall" || echo "")
        
        if [ -n "$proxy_hops" ]; then
            print_status "SUCCESS" "Proxy/gateway hops detected in network path"
            print_status "INFO" "Proxy path: $(echo "$proxy_hops" | head -2 | tr '\n' ' ')"
        else
            print_status "INFO" "No obvious proxy hops detected in traceroute"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Method 4: Environment variable check inside test pod
    print_status "INFO" "Checking proxy environment variables in pod..."
    local pod_proxy_vars
    pod_proxy_vars=$(kubectl exec "$source_pod" -- env | grep -i "proxy\|http_proxy\|https_proxy\|no_proxy" || echo "")
    
    if [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy environment variables found in pod:"
        echo "$pod_proxy_vars" | while read -r var; do
            print_status "INFO" "  $var"
        done
    else
        print_status "INFO" "No proxy environment variables found in pod"
    fi
    
    # Method 5: Connection timing analysis (proxy typically adds latency)
    print_status "INFO" "Analyzing connection timing for proxy detection..."
    local timing_test
    timing_test=$(kubectl exec "$source_pod" -- timeout 15 curl -w "connect:%{time_connect},total:%{time_total}" -s -o /dev/null "https://$test_endpoint" 2>/dev/null || echo "timing_failed")
    
    if [ "$timing_test" != "timing_failed" ]; then
        local connect_time=$(echo "$timing_test" | sed 's/.*connect:\([^,]*\).*/\1/')
        local total_time=$(echo "$timing_test" | sed 's/.*total:\([^,]*\).*/\1/')
        
        print_status "INFO" "Connection timing - Connect: ${connect_time}s, Total: ${total_time}s"
        
        # Proxy connections typically have higher connect times
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$connect_time > 0.5" | bc -l 2>/dev/null || echo 0) )); then
                print_status "INFO" "Higher connect time may indicate proxy routing"
            fi
        fi
    fi
    
    # Method 6: Test multiple endpoints to confirm proxy behavior
    print_status "INFO" "Testing multiple endpoints for consistent proxy behavior..."
    local test_endpoints=("google.com" "github.com" "$test_endpoint")
    local proxy_consistent=0
    local total_tests=0
    
    for endpoint in "${test_endpoints[@]}"; do
        local endpoint_test
        endpoint_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$endpoint" 2>&1)
        
        if echo "$endpoint_test" | grep -q "HTTP/[12]"; then
            ((total_tests++))
            # Check if response shows proxy characteristics
            if echo "$endpoint_test" | grep -qi "proxy\|via:\|x-forwarded"; then
                ((proxy_consistent++))
            fi
        fi
    done
    
    if [ $total_tests -gt 0 ] && [ $proxy_consistent -gt 0 ]; then
        local proxy_percentage=$(echo "scale=0; $proxy_consistent * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
        print_status "INFO" "Proxy indicators found in $proxy_consistent/$total_tests endpoint tests (${proxy_percentage}%)"
        
        if [ $proxy_consistent -eq $total_tests ]; then
            print_status "SUCCESS" "Consistent proxy behavior detected across all test endpoints"
        elif [ $proxy_consistent -gt 0 ]; then
            print_status "WARNING" "Inconsistent proxy behavior - some traffic may bypass proxy"
        fi
    fi
    
    # Summary
    print_status "INFO" "Proxy configuration summary:"
    if [ "$proxy_detected" = "true" ] || [ -n "$proxy_headers" ] || [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy configuration appears to be active and functioning"
    else
        print_status "INFO" "No clear evidence of proxy configuration - traffic appears to be direct"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect Nirmata cluster by checking for Nirmata components
is_nirmata_cluster() {
    # Check for Nirmata-specific resources
    if kubectl get pods -n nirmata-system &>/dev/null; then
        return 0
    elif kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | grep -q nirmata; then
        return 0
    elif kubectl get configmap -A 2>/dev/null | grep -q nirmata; then
        return 0
    else
        return 1
    fi
}

# Function to get Nirmata endpoint from cluster or environment
get_nirmata_endpoint() {
    local endpoint=""
    
    # Method 1: From environment variable
    if [ -n "$NIRMATA_URL" ]; then
        endpoint="$NIRMATA_URL"
    elif [ -n "$NIRMATA_ENDPOINT" ]; then
        endpoint="$NIRMATA_ENDPOINT"
    fi
    
    # Method 2: From Nirmata ConfigMap (if available)
    if [ -z "$endpoint" ]; then
        endpoint=$(kubectl get configmap nirmata-config -n nirmata-system -o jsonpath='{.data.nirmata-url}' 2>/dev/null || echo "")
    fi
    
    # Method 3: From Nirmata agent configuration
    if [ -z "$endpoint" ]; then
        endpoint=$(kubectl get secret nirmata-agent-config -n nirmata-system -o jsonpath='{.data.nirmata-url}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    fi
    
    # Clean up the endpoint (remove protocol if present)
    endpoint=$(echo "$endpoint" | sed 's|^https\?://||' | sed 's|/$||')
    
    echo "$endpoint"
}

# Function to test Nirmata base cluster connectivity
test_nirmata_connectivity() {
    local source_pod=$1
    local nirmata_endpoint=${2:-$(get_nirmata_endpoint)}
    
    if [ -z "$nirmata_endpoint" ]; then
        print_status "WARNING" "No Nirmata endpoint provided and unable to auto-detect"
        print_status "INFO" "Use --nirmata-endpoint <hostname> or set NIRMATA_URL environment variable"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "NIRMATA CONNECTIVITY TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing Nirmata base cluster connectivity: $nirmata_endpoint"
    
    # Test DNS resolution first
    if kubectl exec "$source_pod" -- nslookup "$nirmata_endpoint" &> /dev/null; then
        print_status "SUCCESS" "Nirmata endpoint DNS resolution successful"
        
        # Test HTTPS connectivity (port 443)
        if test_port_connectivity "$source_pod" "$nirmata_endpoint" "443" 15; then
            print_status "SUCCESS" "Nirmata endpoint ($nirmata_endpoint:443) is accessible"
            
            # Test HTTPS handshake and certificate validation
            local ssl_test
            ssl_test=$(kubectl exec "$source_pod" -- timeout 15 openssl s_client -connect "$nirmata_endpoint:443" -servername "$nirmata_endpoint" </dev/null 2>&1)
            
            if echo "$ssl_test" | grep -q "Verify return code: 0 (ok)"; then
                print_status "SUCCESS" "Nirmata SSL/TLS certificate is valid"
            elif echo "$ssl_test" | grep -q "Verify return code:"; then
                local verify_code=$(echo "$ssl_test" | grep "Verify return code:" | sed 's/.*Verify return code: //')
                print_status "WARNING" "Nirmata SSL/TLS verification: $verify_code"
            else
                print_status "WARNING" "Unable to verify Nirmata SSL/TLS certificate"
            fi
            
            # Test HTTP response (basic connectivity)
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$nirmata_endpoint" 2>&1)
            
            if echo "$http_test" | grep -q "HTTP/[12]"; then
                local http_status=$(echo "$http_test" | head -1 | awk '{print $2}')
                if [[ "$http_status" =~ ^[23] ]]; then
                    print_status "SUCCESS" "Nirmata endpoint HTTP response successful (Status: $http_status)"
                else
                    print_status "WARNING" "Nirmata endpoint responded with HTTP status: $http_status"
                fi
            else
                print_status "WARNING" "Unable to get HTTP response from Nirmata endpoint"
            fi
            
        else
            print_status "ERROR" "Nirmata endpoint ($nirmata_endpoint:443) is not accessible"
        fi
    else
        print_status "ERROR" "Nirmata endpoint DNS resolution failed for $nirmata_endpoint"
    fi
    
    # Test common Nirmata API paths
    print_status "INFO" "Testing Nirmata API endpoints..."
    
    local -a nirmata_paths=(
        "/health"
        "/api/health"
        "/users/api/health"
    )
    
    local api_success=false
    for path in "${nirmata_paths[@]}"; do
        local api_test
        api_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -o /dev/null -w "%{http_code}" "https://$nirmata_endpoint$path" 2>/dev/null || echo "000")
        
        if [[ "$api_test" =~ ^[23] ]]; then
            print_status "SUCCESS" "Nirmata API path $path is accessible (HTTP $api_test)"
            api_success=true
            break
        fi
    done
    
    if [ "$api_success" = false ]; then
        print_status "WARNING" "No Nirmata API health endpoints responded successfully"
    fi
    
    # Check for existing Nirmata components in the cluster
    if is_nirmata_cluster; then
        print_status "SUCCESS" "Nirmata components detected in cluster"
        
        # Show status of Nirmata components
        local nirmata_pods
        nirmata_pods=$(kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | grep nirmata | wc -l)
        if [ "$nirmata_pods" -gt 0 ]; then
            print_status "INFO" "Found $nirmata_pods running Nirmata pods in the cluster"
        fi
    else
        print_status "INFO" "No Nirmata components found in cluster (normal for unmanaged clusters)"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect proxy configuration from cluster
detect_proxy_config() {
    local proxy_detected=false
    local proxy_info=""
    
    # Method 1: Check environment variables in kube-system pods
    local proxy_vars
    proxy_vars=$(kubectl get pods -n kube-system -o json 2>/dev/null | jq -r '.items[].spec.containers[].env[]? | select(.name | test("PROXY|proxy")) | .name + "=" + .value' 2>/dev/null | head -5)
    
    if [ -n "$proxy_vars" ]; then
        proxy_detected=true
        proxy_info="Environment variables: $(echo "$proxy_vars" | tr '\n' ' ')"
    fi
    
    # Method 2: Check ConfigMaps for proxy configuration
    local proxy_configmaps
    proxy_configmaps=$(kubectl get configmaps -A -o json 2>/dev/null | jq -r '.items[] | select(.data | keys[] | test("proxy|PROXY")) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | head -3)
    
    if [ -n "$proxy_configmaps" ] && [ "$proxy_detected" = false ]; then
        proxy_detected=true
        proxy_info="ConfigMaps: $proxy_configmaps"
    fi
    
    # Method 3: Check for common proxy settings in node configuration
    local node_proxy
    node_proxy=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' 2>/dev/null | grep -i proxy || echo "")
    
    echo "$proxy_detected|$proxy_info"
}

# Function to test proxy configuration and routing
test_proxy_configuration() {
    local source_pod=$1
    local test_endpoint=${2:-"httpbin.org"}
    
    print_status "INFO" "=========================================="
    print_status "INFO" "PROXY CONFIGURATION TESTS"
    print_status "INFO" "=========================================="
    
    # Detect existing proxy configuration
    local proxy_detection
    proxy_detection=$(detect_proxy_config)
    local proxy_detected=$(echo "$proxy_detection" | cut -d'|' -f1)
    local proxy_info=$(echo "$proxy_detection" | cut -d'|' -f2)
    
    if [ "$proxy_detected" = "true" ]; then
        print_status "INFO" "Proxy configuration detected in cluster: $proxy_info"
    else
        print_status "INFO" "No explicit proxy configuration detected in cluster"
    fi
    
    # Test direct connection first
    print_status "INFO" "Testing direct connection to $test_endpoint"
    local direct_test
    direct_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$test_endpoint" 2>&1)
    
    if echo "$direct_test" | grep -q "HTTP/[12]"; then
        print_status "SUCCESS" "Direct HTTPS connection to $test_endpoint successful"
    else
        print_status "WARNING" "Direct HTTPS connection to $test_endpoint failed"
    fi
    
    # Test with trace to check routing path
    print_status "INFO" "Performing connection trace analysis..."
    
    # Method 1: Check for proxy headers in response
    local proxy_headers
    proxy_headers=$(kubectl exec "$source_pod" -- timeout 15 curl -v "https://$test_endpoint/headers" 2>&1 | grep -i "proxy\|x-forwarded\|via:" || echo "")
    
    if [ -n "$proxy_headers" ]; then
        print_status "SUCCESS" "Proxy headers detected in response - traffic appears to be routed through proxy"
        print_status "INFO" "Proxy evidence: $(echo "$proxy_headers" | head -2 | tr '\n' ' ')"
    fi
    
    # Method 2: DNS resolution analysis for proxy detection
    print_status "INFO" "Analyzing DNS resolution patterns..."
    local dns_trace
    dns_trace=$(kubectl exec "$source_pod" -- nslookup "$test_endpoint" 2>&1)
    
    # Look for proxy-related hostnames in DNS responses
    if echo "$dns_trace" | grep -i "proxy\|gateway\|firewall" | head -3; then
        print_status "SUCCESS" "Proxy-related hostnames detected in DNS resolution"
    else
        print_status "INFO" "No proxy-related hostnames found in DNS resolution"
    fi
    
    # Method 3: Traceroute analysis (if available)
    print_status "INFO" "Testing network path analysis..."
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 20 traceroute "$test_endpoint" 2>&1 | head -10 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for proxy-related hops in traceroute
        local proxy_hops
        proxy_hops=$(echo "$traceroute_output" | grep -i "proxy\|gateway\|firewall" || echo "")
        
        if [ -n "$proxy_hops" ]; then
            print_status "SUCCESS" "Proxy/gateway hops detected in network path"
            print_status "INFO" "Proxy path: $(echo "$proxy_hops" | head -2 | tr '\n' ' ')"
        else
            print_status "INFO" "No obvious proxy hops detected in traceroute"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Method 4: Environment variable check inside test pod
    print_status "INFO" "Checking proxy environment variables in pod..."
    local pod_proxy_vars
    pod_proxy_vars=$(kubectl exec "$source_pod" -- env | grep -i "proxy\|http_proxy\|https_proxy\|no_proxy" || echo "")
    
    if [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy environment variables found in pod:"
        echo "$pod_proxy_vars" | while read -r var; do
            print_status "INFO" "  $var"
        done
    else
        print_status "INFO" "No proxy environment variables found in pod"
    fi
    
    # Method 5: Connection timing analysis (proxy typically adds latency)
    print_status "INFO" "Analyzing connection timing for proxy detection..."
    local timing_test
    timing_test=$(kubectl exec "$source_pod" -- timeout 15 curl -w "connect:%{time_connect},total:%{time_total}" -s -o /dev/null "https://$test_endpoint" 2>/dev/null || echo "timing_failed")
    
    if [ "$timing_test" != "timing_failed" ]; then
        local connect_time=$(echo "$timing_test" | sed 's/.*connect:\([^,]*\).*/\1/')
        local total_time=$(echo "$timing_test" | sed 's/.*total:\([^,]*\).*/\1/')
        
        print_status "INFO" "Connection timing - Connect: ${connect_time}s, Total: ${total_time}s"
        
        # Proxy connections typically have higher connect times
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$connect_time > 0.5" | bc -l 2>/dev/null || echo 0) )); then
                print_status "INFO" "Higher connect time may indicate proxy routing"
            fi
        fi
    fi
    
    # Method 6: Test multiple endpoints to confirm proxy behavior
    print_status "INFO" "Testing multiple endpoints for consistent proxy behavior..."
    local test_endpoints=("google.com" "github.com" "$test_endpoint")
    local proxy_consistent=0
    local total_tests=0
    
    for endpoint in "${test_endpoints[@]}"; do
        local endpoint_test
        endpoint_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$endpoint" 2>&1)
        
        if echo "$endpoint_test" | grep -q "HTTP/[12]"; then
            ((total_tests++))
            # Check if response shows proxy characteristics
            if echo "$endpoint_test" | grep -qi "proxy\|via:\|x-forwarded"; then
                ((proxy_consistent++))
            fi
        fi
    done
    
    if [ $total_tests -gt 0 ] && [ $proxy_consistent -gt 0 ]; then
        local proxy_percentage=$(echo "scale=0; $proxy_consistent * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
        print_status "INFO" "Proxy indicators found in $proxy_consistent/$total_tests endpoint tests (${proxy_percentage}%)"
        
        if [ $proxy_consistent -eq $total_tests ]; then
            print_status "SUCCESS" "Consistent proxy behavior detected across all test endpoints"
        elif [ $proxy_consistent -gt 0 ]; then
            print_status "WARNING" "Inconsistent proxy behavior - some traffic may bypass proxy"
        fi
    fi
    
    # Summary
    print_status "INFO" "Proxy configuration summary:"
    if [ "$proxy_detected" = "true" ] || [ -n "$proxy_headers" ] || [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy configuration appears to be active and functioning"
    else
        print_status "INFO" "No clear evidence of proxy configuration - traffic appears to be direct"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to perform comprehensive network tests
perform_network_tests() {
    local source_pod=$1
    local target_node=$2
    local target_ip=$3
    local node_role=$4
    
    print_status "INFO" "=== Testing connectivity from $source_pod to $node_role node $target_node ==="
    
    # Basic connectivity test
    if [ "$test_basic" = true ]; then
        if kubectl exec "$source_pod" -- ping -c 3 "$target_ip" &> /dev/null; then
            print_status "SUCCESS" "Basic ping connectivity to $target_ip successful"
            
            # Extended packet drop test
            if [ "$test_packet_drops" = true ]; then
                test_packet_drops "$source_pod" "$target_ip" "$target_node" 50 0.1
            fi
            
            # Network stability test
            if [ "$test_stability" = true ]; then
                test_network_stability "$source_pod" "$target_ip" "$target_node" 20
            fi
        else
            print_status "ERROR" "Basic ping connectivity to $target_ip failed"
            return 1
        fi
    fi
    
    case $node_role in
        "master"|"control-plane")
            # Test master node ports
            test_ports "$source_pod" "$target_node" "$target_ip" "${ETCD_PORTS[@]}"
            test_ports "$source_pod" "$target_node" "$target_ip" "${API_SERVER_PORTS[@]}"
            test_ports "$source_pod" "$target_node" "$target_ip" "${KUBELET_PORTS[@]}"
            test_ports "$source_pod" "$target_node" "$target_ip" "${KUBE_SCHEDULER_PORTS[@]}"
            test_ports "$source_pod" "$target_node" "$target_ip" "${KUBE_CONTROLLER_PORTS[@]}"
            ;;
        "worker")
            # Test worker node ports
            test_ports "$source_pod" "$target_node" "$target_ip" "${KUBELET_PORTS[@]}"
            test_ports "$source_pod" "$target_node" "$target_ip" "${WORKER_PORTS[@]}"
            ;;
    esac
    
    # Test CNI-specific ports (common to all nodes)
    if [ "$test_cni" = true ]; then
        local detected_cni=$(detect_cni)
        print_status "INFO" "Detected CNI: $detected_cni"
        test_cni_ports "$source_pod" "$target_node" "$target_ip" "$detected_cni"
    fi
    
    # DNS resolution test - dynamically get kubernetes service IP and domain
    if [ "$test_dns" = true ]; then
        local k8s_svc_ip
        k8s_svc_ip=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.96.0.1")
        local k8s_domain="kubernetes.default.svc.cluster.local"
        
        # Test with kubernetes service domain
        local dns_output
        dns_output=$(kubectl exec "$source_pod" -- nslookup "$k8s_domain" 2>&1)
        
        if echo "$dns_output" | grep -q "Address:.*$k8s_svc_ip"; then
            print_status "SUCCESS" "DNS resolution test passed ($k8s_domain resolved to $k8s_svc_ip)"
        elif echo "$dns_output" | grep -q "Name:.*$k8s_domain"; then
            print_status "SUCCESS" "DNS resolution test passed ($k8s_domain resolved)"
        else
            # Fallback test with kube-dns service
            local kube_dns_output
            kube_dns_output=$(kubectl exec "$source_pod" -- nslookup kube-dns.kube-system.svc.cluster.local 2>&1)
            if echo "$kube_dns_output" | grep -q "Name:.*kube-dns"; then
                print_status "SUCCESS" "DNS resolution test passed (kube-dns.kube-system.svc.cluster.local resolved)"
            else
                print_status "WARNING" "DNS resolution test failed - kubernetes output: $(echo "$dns_output" | head -2)"
            fi
        fi
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect proxy configuration from cluster
detect_proxy_config() {
    local proxy_detected=false
    local proxy_info=""
    
    # Method 1: Check environment variables in kube-system pods
    local proxy_vars
    proxy_vars=$(kubectl get pods -n kube-system -o json 2>/dev/null | jq -r '.items[].spec.containers[].env[]? | select(.name | test("PROXY|proxy")) | .name + "=" + .value' 2>/dev/null | head -5)
    
    if [ -n "$proxy_vars" ]; then
        proxy_detected=true
        proxy_info="Environment variables: $(echo "$proxy_vars" | tr '\n' ' ')"
    fi
    
    # Method 2: Check ConfigMaps for proxy configuration
    local proxy_configmaps
    proxy_configmaps=$(kubectl get configmaps -A -o json 2>/dev/null | jq -r '.items[] | select(.data | keys[] | test("proxy|PROXY")) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | head -3)
    
    if [ -n "$proxy_configmaps" ] && [ "$proxy_detected" = false ]; then
        proxy_detected=true
        proxy_info="ConfigMaps: $proxy_configmaps"
    fi
    
    # Method 3: Check for common proxy settings in node configuration
    local node_proxy
    node_proxy=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' 2>/dev/null | grep -i proxy || echo "")
    
    echo "$proxy_detected|$proxy_info"
}

# Function to test proxy configuration and routing
test_proxy_configuration() {
    local source_pod=$1
    local test_endpoint=${2:-"httpbin.org"}
    
    print_status "INFO" "=========================================="
    print_status "INFO" "PROXY CONFIGURATION TESTS"
    print_status "INFO" "=========================================="
    
    # Detect existing proxy configuration
    local proxy_detection
    proxy_detection=$(detect_proxy_config)
    local proxy_detected=$(echo "$proxy_detection" | cut -d'|' -f1)
    local proxy_info=$(echo "$proxy_detection" | cut -d'|' -f2)
    
    if [ "$proxy_detected" = "true" ]; then
        print_status "INFO" "Proxy configuration detected in cluster: $proxy_info"
    else
        print_status "INFO" "No explicit proxy configuration detected in cluster"
    fi
    
    # Test direct connection first
    print_status "INFO" "Testing direct connection to $test_endpoint"
    local direct_test
    direct_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$test_endpoint" 2>&1)
    
    if echo "$direct_test" | grep -q "HTTP/[12]"; then
        print_status "SUCCESS" "Direct HTTPS connection to $test_endpoint successful"
    else
        print_status "WARNING" "Direct HTTPS connection to $test_endpoint failed"
    fi
    
    # Test with trace to check routing path
    print_status "INFO" "Performing connection trace analysis..."
    
    # Method 1: Check for proxy headers in response
    local proxy_headers
    proxy_headers=$(kubectl exec "$source_pod" -- timeout 15 curl -v "https://$test_endpoint/headers" 2>&1 | grep -i "proxy\|x-forwarded\|via:" || echo "")
    
    if [ -n "$proxy_headers" ]; then
        print_status "SUCCESS" "Proxy headers detected in response - traffic appears to be routed through proxy"
        print_status "INFO" "Proxy evidence: $(echo "$proxy_headers" | head -2 | tr '\n' ' ')"
    fi
    
    # Method 2: DNS resolution analysis for proxy detection
    print_status "INFO" "Analyzing DNS resolution patterns..."
    local dns_trace
    dns_trace=$(kubectl exec "$source_pod" -- nslookup "$test_endpoint" 2>&1)
    
    # Look for proxy-related hostnames in DNS responses
    if echo "$dns_trace" | grep -i "proxy\|gateway\|firewall" | head -3; then
        print_status "SUCCESS" "Proxy-related hostnames detected in DNS resolution"
    else
        print_status "INFO" "No proxy-related hostnames found in DNS resolution"
    fi
    
    # Method 3: Traceroute analysis (if available)
    print_status "INFO" "Testing network path analysis..."
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 20 traceroute "$test_endpoint" 2>&1 | head -10 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for proxy-related hops in traceroute
        local proxy_hops
        proxy_hops=$(echo "$traceroute_output" | grep -i "proxy\|gateway\|firewall" || echo "")
        
        if [ -n "$proxy_hops" ]; then
            print_status "SUCCESS" "Proxy/gateway hops detected in network path"
            print_status "INFO" "Proxy path: $(echo "$proxy_hops" | head -2 | tr '\n' ' ')"
        else
            print_status "INFO" "No obvious proxy hops detected in traceroute"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Method 4: Environment variable check inside test pod
    print_status "INFO" "Checking proxy environment variables in pod..."
    local pod_proxy_vars
    pod_proxy_vars=$(kubectl exec "$source_pod" -- env | grep -i "proxy\|http_proxy\|https_proxy\|no_proxy" || echo "")
    
    if [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy environment variables found in pod:"
        echo "$pod_proxy_vars" | while read -r var; do
            print_status "INFO" "  $var"
        done
    else
        print_status "INFO" "No proxy environment variables found in pod"
    fi
    
    # Method 5: Connection timing analysis (proxy typically adds latency)
    print_status "INFO" "Analyzing connection timing for proxy detection..."
    local timing_test
    timing_test=$(kubectl exec "$source_pod" -- timeout 15 curl -w "connect:%{time_connect},total:%{time_total}" -s -o /dev/null "https://$test_endpoint" 2>/dev/null || echo "timing_failed")
    
    if [ "$timing_test" != "timing_failed" ]; then
        local connect_time=$(echo "$timing_test" | sed 's/.*connect:\([^,]*\).*/\1/')
        local total_time=$(echo "$timing_test" | sed 's/.*total:\([^,]*\).*/\1/')
        
        print_status "INFO" "Connection timing - Connect: ${connect_time}s, Total: ${total_time}s"
        
        # Proxy connections typically have higher connect times
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$connect_time > 0.5" | bc -l 2>/dev/null || echo 0) )); then
                print_status "INFO" "Higher connect time may indicate proxy routing"
            fi
        fi
    fi
    
    # Method 6: Test multiple endpoints to confirm proxy behavior
    print_status "INFO" "Testing multiple endpoints for consistent proxy behavior..."
    local test_endpoints=("google.com" "github.com" "$test_endpoint")
    local proxy_consistent=0
    local total_tests=0
    
    for endpoint in "${test_endpoints[@]}"; do
        local endpoint_test
        endpoint_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$endpoint" 2>&1)
        
        if echo "$endpoint_test" | grep -q "HTTP/[12]"; then
            ((total_tests++))
            # Check if response shows proxy characteristics
            if echo "$endpoint_test" | grep -qi "proxy\|via:\|x-forwarded"; then
                ((proxy_consistent++))
            fi
        fi
    done
    
    if [ $total_tests -gt 0 ] && [ $proxy_consistent -gt 0 ]; then
        local proxy_percentage=$(echo "scale=0; $proxy_consistent * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
        print_status "INFO" "Proxy indicators found in $proxy_consistent/$total_tests endpoint tests (${proxy_percentage}%)"
        
        if [ $proxy_consistent -eq $total_tests ]; then
            print_status "SUCCESS" "Consistent proxy behavior detected across all test endpoints"
        elif [ $proxy_consistent -gt 0 ]; then
            print_status "WARNING" "Inconsistent proxy behavior - some traffic may bypass proxy"
        fi
    fi
    
    # Summary
    print_status "INFO" "Proxy configuration summary:"
    if [ "$proxy_detected" = "true" ] || [ -n "$proxy_headers" ] || [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy configuration appears to be active and functioning"
    else
        print_status "INFO" "No clear evidence of proxy configuration - traffic appears to be direct"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect Nirmata cluster by checking for Nirmata components
is_nirmata_cluster() {
    # Check for Nirmata-specific resources
    if kubectl get pods -n nirmata-system &>/dev/null; then
        return 0
    elif kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | grep -q nirmata; then
        return 0
    elif kubectl get configmap -A 2>/dev/null | grep -q nirmata; then
        return 0
    else
        return 1
    fi
}

# Function to get Nirmata endpoint from cluster or environment
get_nirmata_endpoint() {
    local endpoint=""
    
    # Method 1: From environment variable
    if [ -n "$NIRMATA_URL" ]; then
        endpoint="$NIRMATA_URL"
    elif [ -n "$NIRMATA_ENDPOINT" ]; then
        endpoint="$NIRMATA_ENDPOINT"
    fi
    
    # Method 2: From Nirmata ConfigMap (if available)
    if [ -z "$endpoint" ]; then
        endpoint=$(kubectl get configmap nirmata-config -n nirmata-system -o jsonpath='{.data.nirmata-url}' 2>/dev/null || echo "")
    fi
    
    # Method 3: From Nirmata agent configuration
    if [ -z "$endpoint" ]; then
        endpoint=$(kubectl get secret nirmata-agent-config -n nirmata-system -o jsonpath='{.data.nirmata-url}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    fi
    
    # Clean up the endpoint (remove protocol if present)
    endpoint=$(echo "$endpoint" | sed 's|^https\?://||' | sed 's|/$||')
    
    echo "$endpoint"
}

# Function to test Nirmata base cluster connectivity
test_nirmata_connectivity() {
    local source_pod=$1
    local nirmata_endpoint=${2:-$(get_nirmata_endpoint)}
    
    if [ -z "$nirmata_endpoint" ]; then
        print_status "WARNING" "No Nirmata endpoint provided and unable to auto-detect"
        print_status "INFO" "Use --nirmata-endpoint <hostname> or set NIRMATA_URL environment variable"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "NIRMATA CONNECTIVITY TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing Nirmata base cluster connectivity: $nirmata_endpoint"
    
    # Test DNS resolution first
    if kubectl exec "$source_pod" -- nslookup "$nirmata_endpoint" &> /dev/null; then
        print_status "SUCCESS" "Nirmata endpoint DNS resolution successful"
        
        # Test HTTPS connectivity (port 443)
        if test_port_connectivity "$source_pod" "$nirmata_endpoint" "443" 15; then
            print_status "SUCCESS" "Nirmata endpoint ($nirmata_endpoint:443) is accessible"
            
            # Test HTTPS handshake and certificate validation
            local ssl_test
            ssl_test=$(kubectl exec "$source_pod" -- timeout 15 openssl s_client -connect "$nirmata_endpoint:443" -servername "$nirmata_endpoint" </dev/null 2>&1)
            
            if echo "$ssl_test" | grep -q "Verify return code: 0 (ok)"; then
                print_status "SUCCESS" "Nirmata SSL/TLS certificate is valid"
            elif echo "$ssl_test" | grep -q "Verify return code:"; then
                local verify_code=$(echo "$ssl_test" | grep "Verify return code:" | sed 's/.*Verify return code: //')
                print_status "WARNING" "Nirmata SSL/TLS verification: $verify_code"
            else
                print_status "WARNING" "Unable to verify Nirmata SSL/TLS certificate"
            fi
            
            # Test HTTP response (basic connectivity)
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$nirmata_endpoint" 2>&1)
            
            if echo "$http_test" | grep -q "HTTP/[12]"; then
                local http_status=$(echo "$http_test" | head -1 | awk '{print $2}')
                if [[ "$http_status" =~ ^[23] ]]; then
                    print_status "SUCCESS" "Nirmata endpoint HTTP response successful (Status: $http_status)"
                else
                    print_status "WARNING" "Nirmata endpoint responded with HTTP status: $http_status"
                fi
            else
                print_status "WARNING" "Unable to get HTTP response from Nirmata endpoint"
            fi
            
        else
            print_status "ERROR" "Nirmata endpoint ($nirmata_endpoint:443) is not accessible"
        fi
    else
        print_status "ERROR" "Nirmata endpoint DNS resolution failed for $nirmata_endpoint"
    fi
    
    # Test common Nirmata API paths
    print_status "INFO" "Testing Nirmata API endpoints..."
    
    local -a nirmata_paths=(
        "/health"
        "/api/health"
        "/users/api/health"
    )
    
    local api_success=false
    for path in "${nirmata_paths[@]}"; do
        local api_test
        api_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -o /dev/null -w "%{http_code}" "https://$nirmata_endpoint$path" 2>/dev/null || echo "000")
        
        if [[ "$api_test" =~ ^[23] ]]; then
            print_status "SUCCESS" "Nirmata API path $path is accessible (HTTP $api_test)"
            api_success=true
            break
        fi
    done
    
    if [ "$api_success" = false ]; then
        print_status "WARNING" "No Nirmata API health endpoints responded successfully"
    fi
    
    # Check for existing Nirmata components in the cluster
    if is_nirmata_cluster; then
        print_status "SUCCESS" "Nirmata components detected in cluster"
        
        # Show status of Nirmata components
        local nirmata_pods
        nirmata_pods=$(kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | grep nirmata | wc -l)
        if [ "$nirmata_pods" -gt 0 ]; then
            print_status "INFO" "Found $nirmata_pods running Nirmata pods in the cluster"
        fi
    else
        print_status "INFO" "No Nirmata components found in cluster (normal for unmanaged clusters)"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to detect proxy configuration from cluster
detect_proxy_config() {
    local proxy_detected=false
    local proxy_info=""
    
    # Method 1: Check environment variables in kube-system pods
    local proxy_vars
    proxy_vars=$(kubectl get pods -n kube-system -o json 2>/dev/null | jq -r '.items[].spec.containers[].env[]? | select(.name | test("PROXY|proxy")) | .name + "=" + .value' 2>/dev/null | head -5)
    
    if [ -n "$proxy_vars" ]; then
        proxy_detected=true
        proxy_info="Environment variables: $(echo "$proxy_vars" | tr '\n' ' ')"
    fi
    
    # Method 2: Check ConfigMaps for proxy configuration
    local proxy_configmaps
    proxy_configmaps=$(kubectl get configmaps -A -o json 2>/dev/null | jq -r '.items[] | select(.data | keys[] | test("proxy|PROXY")) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | head -3)
    
    if [ -n "$proxy_configmaps" ] && [ "$proxy_detected" = false ]; then
        proxy_detected=true
        proxy_info="ConfigMaps: $proxy_configmaps"
    fi
    
    # Method 3: Check for common proxy settings in node configuration
    local node_proxy
    node_proxy=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' 2>/dev/null | grep -i proxy || echo "")
    
    echo "$proxy_detected|$proxy_info"
}

# Function to test proxy configuration and routing
test_proxy_configuration() {
    local source_pod=$1
    local test_endpoint=${2:-"httpbin.org"}
    
    print_status "INFO" "=========================================="
    print_status "INFO" "PROXY CONFIGURATION TESTS"
    print_status "INFO" "=========================================="
    
    # Detect existing proxy configuration
    local proxy_detection
    proxy_detection=$(detect_proxy_config)
    local proxy_detected=$(echo "$proxy_detection" | cut -d'|' -f1)
    local proxy_info=$(echo "$proxy_detection" | cut -d'|' -f2)
    
    if [ "$proxy_detected" = "true" ]; then
        print_status "INFO" "Proxy configuration detected in cluster: $proxy_info"
    else
        print_status "INFO" "No explicit proxy configuration detected in cluster"
    fi
    
    # Test direct connection first
    print_status "INFO" "Testing direct connection to $test_endpoint"
    local direct_test
    direct_test=$(kubectl exec "$source_pod" -- timeout 15 curl -s -I "https://$test_endpoint" 2>&1)
    
    if echo "$direct_test" | grep -q "HTTP/[12]"; then
        print_status "SUCCESS" "Direct HTTPS connection to $test_endpoint successful"
    else
        print_status "WARNING" "Direct HTTPS connection to $test_endpoint failed"
    fi
    
    # Test with trace to check routing path
    print_status "INFO" "Performing connection trace analysis..."
    
    # Method 1: Check for proxy headers in response
    local proxy_headers
    proxy_headers=$(kubectl exec "$source_pod" -- timeout 15 curl -v "https://$test_endpoint/headers" 2>&1 | grep -i "proxy\|x-forwarded\|via:" || echo "")
    
    if [ -n "$proxy_headers" ]; then
        print_status "SUCCESS" "Proxy headers detected in response - traffic appears to be routed through proxy"
        print_status "INFO" "Proxy evidence: $(echo "$proxy_headers" | head -2 | tr '\n' ' ')"
    fi
    
    # Method 2: DNS resolution analysis for proxy detection
    print_status "INFO" "Analyzing DNS resolution patterns..."
    local dns_trace
    dns_trace=$(kubectl exec "$source_pod" -- nslookup "$test_endpoint" 2>&1)
    
    # Look for proxy-related hostnames in DNS responses
    if echo "$dns_trace" | grep -i "proxy\|gateway\|firewall" | head -3; then
        print_status "SUCCESS" "Proxy-related hostnames detected in DNS resolution"
    else
        print_status "INFO" "No proxy-related hostnames found in DNS resolution"
    fi
    
    # Method 3: Traceroute analysis (if available)
    print_status "INFO" "Testing network path analysis..."
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 20 traceroute "$test_endpoint" 2>&1 | head -10 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for proxy-related hops in traceroute
        local proxy_hops
        proxy_hops=$(echo "$traceroute_output" | grep -i "proxy\|gateway\|firewall" || echo "")
        
        if [ -n "$proxy_hops" ]; then
            print_status "SUCCESS" "Proxy/gateway hops detected in network path"
            print_status "INFO" "Proxy path: $(echo "$proxy_hops" | head -2 | tr '\n' ' ')"
        else
            print_status "INFO" "No obvious proxy hops detected in traceroute"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Method 4: Environment variable check inside test pod
    print_status "INFO" "Checking proxy environment variables in pod..."
    local pod_proxy_vars
    pod_proxy_vars=$(kubectl exec "$source_pod" -- env | grep -i "proxy\|http_proxy\|https_proxy\|no_proxy" || echo "")
    
    if [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy environment variables found in pod:"
        echo "$pod_proxy_vars" | while read -r var; do
            print_status "INFO" "  $var"
        done
    else
        print_status "INFO" "No proxy environment variables found in pod"
    fi
    
    # Method 5: Connection timing analysis (proxy typically adds latency)
    print_status "INFO" "Analyzing connection timing for proxy detection..."
    local timing_test
    timing_test=$(kubectl exec "$source_pod" -- timeout 15 curl -w "connect:%{time_connect},total:%{time_total}" -s -o /dev/null "https://$test_endpoint" 2>/dev/null || echo "timing_failed")
    
    if [ "$timing_test" != "timing_failed" ]; then
        local connect_time=$(echo "$timing_test" | sed 's/.*connect:\([^,]*\).*/\1/')
        local total_time=$(echo "$timing_test" | sed 's/.*total:\([^,]*\).*/\1/')
        
        print_status "INFO" "Connection timing - Connect: ${connect_time}s, Total: ${total_time}s"
        
        # Proxy connections typically have higher connect times
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$connect_time > 0.5" | bc -l 2>/dev/null || echo 0) )); then
                print_status "INFO" "Higher connect time may indicate proxy routing"
            fi
        fi
    fi
    
    # Method 6: Test multiple endpoints to confirm proxy behavior
    print_status "INFO" "Testing multiple endpoints for consistent proxy behavior..."
    local test_endpoints=("google.com" "github.com" "$test_endpoint")
    local proxy_consistent=0
    local total_tests=0
    
    for endpoint in "${test_endpoints[@]}"; do
        local endpoint_test
        endpoint_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$endpoint" 2>&1)
        
        if echo "$endpoint_test" | grep -q "HTTP/[12]"; then
            ((total_tests++))
            # Check if response shows proxy characteristics
            if echo "$endpoint_test" | grep -qi "proxy\|via:\|x-forwarded"; then
                ((proxy_consistent++))
            fi
        fi
    done
    
    if [ $total_tests -gt 0 ] && [ $proxy_consistent -gt 0 ]; then
        local proxy_percentage=$(echo "scale=0; $proxy_consistent * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
        print_status "INFO" "Proxy indicators found in $proxy_consistent/$total_tests endpoint tests (${proxy_percentage}%)"
        
        if [ $proxy_consistent -eq $total_tests ]; then
            print_status "SUCCESS" "Consistent proxy behavior detected across all test endpoints"
        elif [ $proxy_consistent -gt 0 ]; then
            print_status "WARNING" "Inconsistent proxy behavior - some traffic may bypass proxy"
        fi
    fi
    
    # Summary
    print_status "INFO" "Proxy configuration summary:"
    if [ "$proxy_detected" = "true" ] || [ -n "$proxy_headers" ] || [ -n "$pod_proxy_vars" ]; then
        print_status "SUCCESS" "Proxy configuration appears to be active and functioning"
    else
        print_status "INFO" "No clear evidence of proxy configuration - traffic appears to be direct"
    fi
    
    echo ""
}

# Function to test firewall port blocking
test_firewall_port_blocking() {
    local source_pod=$1
    local test_endpoint=$2
    local test_port=$3
    
    if [ -z "$test_endpoint" ] || [ -z "$test_port" ]; then
        print_status "WARNING" "Firewall test skipped - endpoint and port must be specified"
        print_status "INFO" "Use --firewall-test-endpoint <hostname> --firewall-test-port <port>"
        return 1
    fi
    
    print_status "INFO" "=========================================="
    print_status "INFO" "FIREWALL PORT BLOCKING TESTS"
    print_status "INFO" "=========================================="
    
    print_status "INFO" "Testing firewall rules for $test_endpoint:$test_port"
    
    # Test 1: DNS Resolution first
    print_status "INFO" "Step 1: Testing DNS resolution for $test_endpoint"
    if kubectl exec "$source_pod" -- nslookup "$test_endpoint" &> /dev/null; then
        print_status "SUCCESS" "DNS resolution successful for $test_endpoint"
    else
        print_status "ERROR" "DNS resolution failed for $test_endpoint - cannot proceed with port test"
        return 1
    fi
    
    # Test 2: Basic port connectivity using netcat
    print_status "INFO" "Step 2: Testing port connectivity using netcat"
    local nc_result
    nc_result=$(kubectl exec "$source_pod" -- timeout 15 nc -zv "$test_endpoint" "$test_port" 2>&1)
    local nc_exit_code=$?
    
    if [ $nc_exit_code -eq 0 ]; then
        print_status "SUCCESS" "Port $test_port is accessible on $test_endpoint"
    else
        print_status "ERROR" "Port $test_port is blocked or service not available on $test_endpoint"
        print_status "INFO" "Netcat output: $nc_result"
    fi
    
    # Test 3: TCP connection test with telnet (if available)
    print_status "INFO" "Step 3: Testing TCP connection with telnet"
    local telnet_result
    telnet_result=$(kubectl exec "$source_pod" -- timeout 10 sh -c "echo '' | telnet $test_endpoint $test_port" 2>&1 || echo "telnet_failed")
    
    if echo "$telnet_result" | grep -q "Connected\|Escape character"; then
        print_status "SUCCESS" "Telnet connection successful to $test_endpoint:$test_port"
    elif echo "$telnet_result" | grep -q "Connection refused"; then
        print_status "WARNING" "Connection refused - service may not be running on port $test_port"
    elif echo "$telnet_result" | grep -q "timeout\|No route\|Network unreachable"; then
        print_status "ERROR" "Connection timeout/unreachable - likely firewall blocking"
    else
        print_status "INFO" "Telnet test inconclusive"
    fi
    
    # Test 4: Multiple connection attempts to detect intermittent blocking
    print_status "INFO" "Step 4: Testing for intermittent firewall blocking (10 attempts)"
    local success_count=0
    local total_attempts=10
    
    for i in $(seq 1 $total_attempts); do
        if kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$test_port" &>/dev/null; then
            ((success_count++))
        fi
        sleep 0.5
    done
    
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
    print_status "INFO" "Port accessibility: $success_count/$total_attempts attempts successful (${success_rate}%)"
    
    if [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Consistent port access - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent port blocking detected - possible firewall rules or rate limiting"
    else
        print_status "ERROR" "Complete port blocking - firewall likely blocking all traffic to port $test_port"
    fi
    
    # Test 5: Protocol-specific tests based on common port usage
    print_status "INFO" "Step 5: Protocol-specific connectivity tests"
    case $test_port in
        80)
            print_status "INFO" "Testing HTTP connectivity (port 80)"
            local http_test
            http_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "http://$test_endpoint" 2>&1)
            if echo "$http_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTP service responding on port 80"
            else
                print_status "WARNING" "Port 80 accessible but no HTTP service detected"
            fi
            ;;
        443)
            print_status "INFO" "Testing HTTPS connectivity (port 443)"
            local https_test
            https_test=$(kubectl exec "$source_pod" -- timeout 10 curl -s -I "https://$test_endpoint" 2>&1)
            if echo "$https_test" | grep -q "HTTP/"; then
                print_status "SUCCESS" "HTTPS service responding on port 443"
            else
                print_status "WARNING" "Port 443 accessible but no HTTPS service detected"
            fi
            ;;
        22)
            print_status "INFO" "Testing SSH connectivity (port 22)"
            local ssh_test
            ssh_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if echo "$ssh_test" | grep -q "SSH"; then
                print_status "SUCCESS" "SSH service responding on port 22"
            else
                print_status "WARNING" "Port 22 accessible but no SSH banner detected"
            fi
            ;;
        *)
            print_status "INFO" "Testing generic TCP connectivity for port $test_port"
            local generic_test
            generic_test=$(kubectl exec "$source_pod" -- timeout 5 nc "$test_endpoint" "$test_port" </dev/null 2>&1)
            if [ $? -eq 0 ]; then
                print_status "SUCCESS" "TCP connection established to port $test_port"
            fi
            ;;
    esac
    
    # Test 6: Traceroute analysis to identify where blocking occurs
    print_status "INFO" "Step 6: Network path analysis to identify blocking point"
    local traceroute_output
    traceroute_output=$(kubectl exec "$source_pod" -- timeout 30 traceroute "$test_endpoint" 2>&1 | head -15 || echo "traceroute_unavailable")
    
    if [ "$traceroute_output" != "traceroute_unavailable" ]; then
        # Look for patterns indicating firewall blocking
        local last_hop
        last_hop=$(echo "$traceroute_output" | grep -v "traceroute\|^\s*$" | tail -1)
        
        if echo "$last_hop" | grep -q "\*\s*\*\s*\*"; then
            print_status "WARNING" "Traceroute shows timeout pattern - possible firewall blocking at network boundary"
        elif echo "$traceroute_output" | grep -q "!X\|!N\|!H"; then
            print_status "ERROR" "Traceroute shows explicit blocking (ICMP error codes)"
        else
            print_status "SUCCESS" "Traceroute completed successfully - no obvious network-level blocking"
        fi
    else
        print_status "INFO" "Traceroute not available for path analysis"
    fi
    
    # Test 7: Alternative port test to compare blocking behavior
    print_status "INFO" "Step 7: Comparative test with alternative ports"
    local alt_ports=()
    
    case $test_port in
        443) alt_ports=(80 8080) ;;
        80) alt_ports=(443 8443) ;;
        22) alt_ports=(23 2222) ;;
        *) alt_ports=(80 443) ;;
    esac
    
    for alt_port in "${alt_ports[@]}"; do
        if [ "$alt_port" != "$test_port" ]; then
            local alt_test
            alt_test=$(kubectl exec "$source_pod" -- timeout 5 nc -z "$test_endpoint" "$alt_port" 2>&1)
            if [ $? -eq 0 ]; then
                print_status "INFO" "Alternative port $alt_port is accessible - suggests selective port blocking"
                break
            fi
        fi
    done
    
    # Test 8: UDP test if applicable
    if [ "$test_port" -eq 53 ] || [ "$test_port" -eq 123 ] || [ "$test_port" -eq 161 ]; then
        print_status "INFO" "Step 8: Testing UDP connectivity for port $test_port"
        local udp_test
        udp_test=$(kubectl exec "$source_pod" -- timeout 5 nc -u -z "$test_endpoint" "$test_port" 2>&1)
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "UDP port $test_port appears accessible"
        else
            print_status "WARNING" "UDP port $test_port may be blocked (UDP testing is less reliable)"
        fi
    fi
    
    # Summary and recommendations
    print_status "INFO" "Firewall test summary for $test_endpoint:$test_port"
    
    if [ $nc_exit_code -eq 0 ] && [ "$success_count" -eq "$total_attempts" ]; then
        print_status "SUCCESS" "Port $test_port is fully accessible - no firewall blocking detected"
    elif [ "$success_count" -gt 0 ]; then
        print_status "WARNING" "Intermittent connectivity issues detected - check for:"
        print_status "INFO" "  - Rate limiting or connection throttling"
        print_status "INFO" "  - Load balancer health checks"
        print_status "INFO" "  - Dynamic firewall rules"
    else
        print_status "ERROR" "Port $test_port appears to be blocked - check for:"
        print_status "INFO" "  - Corporate firewall rules"
        print_status "INFO" "  - Cloud security groups (AWS/Azure/GCP)"
        print_status "INFO" "  - Kubernetes Network Policies"
        print_status "INFO" "  - Service mesh policies (Istio/Linkerd)"
    fi
    
    echo ""
}

# Function to cleanup netshoot pods
cleanup_pods() {
    print_status "INFO" "Cleaning up netshoot pods..."
    kubectl delete pods -l app=netshoot-troubleshoot --ignore-not-found=true
    print_status "SUCCESS" "Cleanup completed"
}

# Function to generate network report
generate_report() {
    local report_file="network-troubleshoot-report-$(date +%Y%m%d-%H%M%S).txt"
    print_status "INFO" "Generating network troubleshooting report: $report_file"
    
    {
        echo "Kubernetes Network Troubleshooting Report"
        echo "Generated on: $(date)"
        echo "Cluster Info:"
        kubectl cluster-info
        echo ""
        echo "Node Information:"
        kubectl get nodes -o wide
        echo ""
        echo "Network Policies:"
        kubectl get networkpolicies --all-namespaces
        echo ""
        echo "Services:"
        kubectl get services --all-namespaces
        echo ""
    } > "$report_file"
    
    print_status "SUCCESS" "Report saved to $report_file"
}

# Main function
main() {
    local skip_cleanup=false
    local generate_report_flag=false
    local test_basic=true
    local test_packet_drops=true
    local test_stability=true
    local test_cni=true
    local test_dns=true
    local test_aws=true
    local test_azure=true
    local test_nirmata=true
    local test_proxy=true
    local test_firewall=true
    local nirmata_endpoint=""
    local proxy_test_endpoint="httpbin.org"
    local firewall_test_endpoint=""
    local firewall_test_port=""
    local quick_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-cleanup)
                skip_cleanup=true
                shift
                ;;
            --report)
                generate_report_flag=true
                shift
                ;;
            --basic-only)
                test_basic=true
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=false
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --no-packet-drops)
                test_packet_drops=false
                shift
                ;;
            --no-stability)
                test_stability=false
                shift
                ;;
            --no-cni)
                test_cni=false
                shift
                ;;
            --no-dns)
                test_dns=false
                shift
                ;;
            --no-aws)
                test_aws=false
                shift
                ;;
            --no-azure)
                test_azure=false
                shift
                ;;
            --no-nirmata)
                test_nirmata=false
                shift
                ;;
            --no-proxy)
                test_proxy=false
                shift
                ;;
            --no-firewall)
                test_firewall=false
                shift
                ;;
            --nirmata-endpoint)
                nirmata_endpoint="$2"
                shift 2
                ;;
            --proxy-test-endpoint)
                proxy_test_endpoint="$2"
                shift 2
                ;;
            --firewall-test-endpoint)
                firewall_test_endpoint="$2"
                shift 2
                ;;
            --firewall-test-port)
                firewall_test_port="$2"
                shift 2
                ;;
            --nirmata-only)
                test_basic=false
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=false
                test_nirmata=true
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --proxy-only)
                test_basic=false
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=false
                test_nirmata=false
                test_proxy=true
                test_firewall=false
                shift
                ;;
            --firewall-only)
                test_basic=false
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=false
                test_nirmata=false
                test_proxy=false
                test_firewall=true
                shift
                ;;
            --quick)
                quick_mode=true
                test_packet_drops=false
                test_stability=false
                shift
                ;;
            --connectivity-only)
                test_basic=true
                test_packet_drops=false
                test_stability=false
                test_cni=true
                test_dns=true
                test_aws=false
                test_azure=false
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --aws-only)
                test_basic=false
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=true
                test_azure=false
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --azure-only)
                test_basic=false
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=true
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --cloud-only)
                test_basic=false
                test_packet_drops=false
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=true
                test_azure=true
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --packet-drops-only)
                test_basic=true
                test_packet_drops=true
                test_stability=false
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=false
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            --stability-only)
                test_basic=true
                test_packet_drops=false
                test_stability=true
                test_cni=false
                test_dns=false
                test_aws=false
                test_azure=false
                test_nirmata=false
                test_proxy=false
                test_firewall=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_status "ERROR" "Unknown option: $1"
                echo "Use --help to see available options"
                exit 1
                ;;
        esac
    done
    
    print_status "INFO" "Starting Kubernetes network troubleshooting..."
    
    # Check prerequisites
    check_kubectl
    
    # Get node information
    master_nodes=($(get_nodes "master"))
    if [ ${#master_nodes[@]} -eq 0 ]; then
        master_nodes=($(get_nodes "control-plane"))
    fi
    worker_nodes=($(get_nodes "worker"))
    
    # Handle empty arrays safely
    if [ -z "${worker_nodes:-}" ]; then
        worker_nodes=()
    fi
    
    # For GKE, if no master nodes found, treat all nodes as worker nodes
    if [ ${#master_nodes[@]} -eq 0 ] && [ ${#worker_nodes[@]} -gt 0 ]; then
        print_status "INFO" "GKE managed cluster detected - master nodes are managed by Google"
        # We'll test worker-to-worker communication instead
    elif [ ${#master_nodes[@]} -eq 0 ] && [ ${#worker_nodes[@]} -eq 0 ]; then
        print_status "ERROR" "No nodes found in cluster"
        exit 1
    fi
    
    print_status "INFO" "Found ${#master_nodes[@]} master nodes and ${#worker_nodes[@]} worker nodes"
    
    # Deploy netshoot pods on all nodes
    all_nodes=()
    if [ ${#master_nodes[@]} -gt 0 ]; then
        all_nodes+=("${master_nodes[@]}")
    fi
    if [ ${#worker_nodes[@]} -gt 0 ]; then
        all_nodes+=("${worker_nodes[@]}")
    fi
    deployed_pods=()
    
    for node in "${all_nodes[@]}"; do
        if deploy_netshoot "$node"; then
            deployed_pods+=("netshoot-$node")
        fi
    done
    
    if [ ${#deployed_pods[@]} -eq 0 ]; then
        print_status "ERROR" "Failed to deploy any netshoot pods"
        exit 1
    fi
    
    # Test Case 1: Master-to-Master Communication (skip for GKE)
    if [ ${#master_nodes[@]} -gt 0 ]; then
        print_status "INFO" "=========================================="
        print_status "INFO" "TEST CASE 1: Master-to-Master Communication"
        print_status "INFO" "=========================================="
        
        for source_node in "${master_nodes[@]}"; do
            source_pod="netshoot-$source_node"
            if [[ " ${deployed_pods[@]} " =~ " ${source_pod} " ]]; then
                for target_node in "${master_nodes[@]}"; do
                    if [ "$source_node" != "$target_node" ]; then
                        target_ip=$(get_node_ip "$target_node")
                        perform_network_tests "$source_pod" "$target_node" "$target_ip" "master"
                    fi
                done
            fi
        done
    else
        print_status "INFO" "=========================================="
        print_status "INFO" "Skipping Master-to-Master tests (GKE managed control plane)"
        print_status "INFO" "=========================================="
    fi
    
    # Test Case 2: Worker-to-Master and Worker-to-Worker Communication
    print_status "INFO" "=========================================="
    if [ ${#master_nodes[@]} -gt 0 ]; then
        print_status "INFO" "TEST CASE 2: Worker-to-Master and Worker-to-Worker Communication"
    else
        print_status "INFO" "TEST CASE 2: Worker-to-Worker Communication (GKE)"
    fi
    print_status "INFO" "=========================================="
    
    if [ ${#worker_nodes[@]} -gt 0 ]; then
        for source_node in "${worker_nodes[@]}"; do
            source_pod="netshoot-$source_node"
            if [[ " ${deployed_pods[@]} " =~ " ${source_pod} " ]]; then
                # Test worker to masters (only if masters exist)
                if [ ${#master_nodes[@]} -gt 0 ]; then
                    for target_node in "${master_nodes[@]}"; do
                        target_ip=$(get_node_ip "$target_node")
                        perform_network_tests "$source_pod" "$target_node" "$target_ip" "master"
                    done
                fi
                
                # Test worker to other workers
                for target_node in "${worker_nodes[@]}"; do
                    if [ "$source_node" != "$target_node" ]; then
                        target_ip=$(get_node_ip "$target_node")
                        perform_network_tests "$source_pod" "$target_node" "$target_ip" "worker"
                    fi
                done
            fi
        done
    fi
    
    # Cloud provider-specific tests
    if [ "$test_aws" = true ] && is_eks_cluster; then
        print_status "INFO" "EKS cluster detected - running AWS-specific connectivity tests"
        if [ ${#deployed_pods[@]} -gt 0 ]; then
            test_eks_networking "${deployed_pods[0]}"
        fi
    elif [ "$test_azure" = true ] && is_aks_cluster; then
        print_status "INFO" "AKS cluster detected - running Azure-specific connectivity tests"
        if [ ${#deployed_pods[@]} -gt 0 ]; then
            test_aks_networking "${deployed_pods[0]}"
        fi
    elif [ "$test_aws" = true ] || [ "$test_azure" = true ]; then
        if is_eks_cluster && [ "$test_aws" = false ]; then
            print_status "INFO" "EKS cluster detected but AWS tests disabled"
        elif is_aks_cluster && [ "$test_azure" = false ]; then
            print_status "INFO" "AKS cluster detected but Azure tests disabled"
        else
            print_status "INFO" "Non-cloud managed cluster detected - skipping cloud-specific tests"
        fi
    fi
    
    # Nirmata connectivity tests
    if [ "$test_nirmata" = true ]; then
        if [ ${#deployed_pods[@]} -gt 0 ]; then
            test_nirmata_connectivity "${deployed_pods[0]}" "$nirmata_endpoint"
        fi
    fi
    
    # Proxy configuration tests
    if [ "$test_proxy" = true ]; then
        if [ ${#deployed_pods[@]} -gt 0 ]; then
            test_proxy_configuration "${deployed_pods[0]}" "$proxy_test_endpoint"
        fi
    fi
    
    # Firewall port blocking tests
    if [ "$test_firewall" = true ]; then
        if [ ${#deployed_pods[@]} -gt 0 ]; then
            test_firewall_port_blocking "${deployed_pods[0]}" "$firewall_test_endpoint" "$firewall_test_port"
        fi
    fi
    
    # Generate report if requested
    if [ "$generate_report_flag" = true ]; then
        generate_report
    fi
    
    # Cleanup unless explicitly skipped
    if [ "$skip_cleanup" = false ]; then
        cleanup_pods
    else
        print_status "INFO" "Skipping cleanup. Netshoot pods are still running for manual investigation."
        print_status "INFO" "To cleanup manually, run: kubectl delete pods -l app=netshoot-troubleshoot"
    fi
    
    print_status "SUCCESS" "Network troubleshooting completed!"
}

# Trap to ensure cleanup on script exit
trap 'cleanup_pods' EXIT

# Run main function
main "$@"