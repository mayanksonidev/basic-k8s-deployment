#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default flag options
BUILD_IMAGE=true

# Resolve directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--build)
            BUILD_IMAGE=true
            shift
            ;;
        -s|--skip-build|--no-build)
            BUILD_IMAGE=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -b, --build       Build the Docker image before deploying (default)"
            echo "  -s, --skip-build  Skip building the Docker image (use existing image)"
            echo "  -h, --help        Display this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use '$0 --help' for usage instructions."
            exit 1
            ;;
    esac
done

log_info "Starting deployment test workflow..."

# 1. Check prerequisites
REQUIRED_TOOLS=("kubectl" "curl")
if [ "$BUILD_IMAGE" = true ]; then
    REQUIRED_TOOLS+=("docker")
fi

for cmd in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required tool '$cmd' is not installed or not in PATH."
        exit 1
    fi
done

# Cleanup handler on script exit
cleanup() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        log_info "Stopping background port-forward (PID: $PORT_FORWARD_PID)..."
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# 2. Clean existing Kubernetes deployments and resources
log_info "Step 1: Cleaning up existing Kubernetes resources..."
kubectl delete -f k8s/ --ignore-not-found=true
kubectl delete -f k8s/mysql-k8s/ --ignore-not-found=true

# Wait for resources to clear
log_info "Waiting for old resources to clear..."
sleep 3

# 3. Build Docker image (Optional based on flag)
IMAGE_NAME="node-app:2.0"
if [ "$BUILD_IMAGE" = true ]; then
    log_info "Step 2: Building Docker image '$IMAGE_NAME'..."
    docker build -t "$IMAGE_NAME" ./node-app

    # If using Minikube or Kind, load image into cluster environment if applicable
    if command -v minikube &>/dev/null && minikube status &>/dev/null; then
        log_info "Minikube detected. Loading Docker image into Minikube..."
        minikube image load "$IMAGE_NAME" || log_warn "Failed to load image into Minikube automatically."
    elif command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q .; then
        CLUSTER_NAME=$(kind get clusters 2>/dev/null | head -n 1)
        log_info "Kind cluster '$CLUSTER_NAME' detected. Loading Docker image..."
        kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME" || log_warn "Failed to load image into Kind."
    fi
else
    log_info "Step 2: Skipping Docker image build (as requested via flag)."
fi

# 4. Deploy both components (MySQL & Node App)
log_info "Step 3: Deploying MySQL database component..."
kubectl apply -f k8s/mysql-k8s/secret.yaml
kubectl apply -f k8s/mysql-k8s/configmap.yaml
kubectl apply -f k8s/mysql-k8s/pvc.yaml
kubectl apply -f k8s/mysql-k8s/deployment.yaml
kubectl apply -f k8s/mysql-k8s/service.yaml

log_info "Step 4: Deploying Node.js application component..."
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# 5. Wait for readiness
log_info "Step 5: Waiting for MySQL deployment rollout..."
kubectl rollout status deployment/mysql --timeout=180s

log_info "Waiting for Node.js deployment rollout..."
kubectl rollout status deployment/node-app-deployment --timeout=180s

log_info "Waiting for Node.js pod to reach Ready status (MySQL connection established)..."
kubectl wait --for=condition=ready pod -l app=node-app --timeout=120s

log_success "Both components deployed successfully and are ready!"

# 6. Test server access via curl
log_info "Step 6: Testing access to Node.js application..."

NODE_PORT=30085
BASE_URL=""

# Check if NodePort 30085 is directly reachable (e.g. Docker Desktop / Kubeadm local node)
if curl -s --connect-timeout 2 "http://localhost:$NODE_PORT/" >/dev/null 2>&1; then
    log_info "Direct NodePort access detected on http://localhost:$NODE_PORT"
    BASE_URL="http://localhost:$NODE_PORT"
else
    # Fallback to port forwarding
    TEST_PORT=30080
    log_info "Establishing background port-forwarding on http://localhost:$TEST_PORT -> svc/node-app-service:80..."
    kubectl port-forward svc/node-app-service "$TEST_PORT":80 >/dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    BASE_URL="http://localhost:$TEST_PORT"
    sleep 3
fi

# Execute curl request with retries
TEST_URL="$BASE_URL/"
log_info "Executing curl command: curl -sS $TEST_URL"

MAX_RETRIES=10
ATTEMPT=1
SUCCESS=0

while [ $ATTEMPT -le $MAX_RETRIES ]; do
    HTTP_STATUS=$(curl -s -o /tmp/curl_response.txt -w "%{http_code}" "$TEST_URL" || echo "000")
    if [ "$HTTP_STATUS" -eq 200 ]; then
        SUCCESS=1
        break
    fi
    log_warn "Attempt $ATTEMPT/$MAX_RETRIES: HTTP Status $HTTP_STATUS. Retrying in 2 seconds..."
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

RESPONSE_BODY=$(cat /tmp/curl_response.txt 2>/dev/null || echo "")

if [ "$SUCCESS" -eq 1 ]; then
    log_success "Access test PASSED! (HTTP Status: $HTTP_STATUS)"
    echo -e "${GREEN}Response:${NC}\n$RESPONSE_BODY\n"
else
    log_error "Access test FAILED! (HTTP Status: $HTTP_STATUS)"
    echo -e "${RED}Response:${NC}\n$RESPONSE_BODY\n"
    exit 1
fi

# Test additional endpoints
log_info "Testing additional endpoint /message1..."
curl -sS "$BASE_URL/message1" && echo -e "\n"

log_info "Testing additional endpoint /message2..."
curl -sS "$BASE_URL/message2" && echo -e "\n"

log_info "Testing additional endpoint /secrets..."
curl -sS "$BASE_URL/secrets" && echo -e "\n"

log_info "Testing database integration endpoint /users..."
curl -sS "$BASE_URL/users" && echo -e "\n"

log_success "All endpoint tests completed successfully!"
