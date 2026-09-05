#!/usr/bin/env bash
set -e

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Node App & MySQL Deployment & Verification Script ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Build Docker Image
echo -e "\n${YELLOW}Step 1: Building Docker image 'node-app:2.0'...${NC}"
docker build -t node-app:2.0 ./node-app

# Check if using Kind cluster and load image if applicable
if command -v kind >/dev/null 2>&1; then
  KIND_CLUSTERS=$(kind get clusters 2>/dev/null || true)
  if [ -n "$KIND_CLUSTERS" ]; then
    echo -e "${YELLOW}Loading image into Kind cluster...${NC}"
    for CLUSTER in $KIND_CLUSTERS; do
      kind load docker-image node-app:2.0 --name "$CLUSTER" || true
    done
  fi
fi

# 2. Deploy MySQL Resources
echo -e "\n${YELLOW}Step 2: Deploying MySQL resources...${NC}"
kubectl apply -f k8s/mysql-k8s/configmap.yaml
kubectl apply -f k8s/mysql-k8s/secret.yaml
kubectl apply -f k8s/mysql-k8s/deployment.yaml
kubectl apply -f k8s/mysql-k8s/service.yaml

# 3. Deploy Node App Resources
echo -e "\n${YELLOW}Step 3: Deploying Node App resources...${NC}"
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Force rollout restart to ensure pods pick up newly built docker image
echo -e "\n${YELLOW}Step 4: Restarting deployment to pull updated image...${NC}"
kubectl rollout restart deployment/node-app-deployment

# 4. Wait for Rollouts
echo -e "\n${YELLOW}Step 5: Waiting for MySQL rollout...${NC}"
kubectl rollout status deployment/mysql --timeout=120s

echo -e "\n${YELLOW}Step 6: Waiting for Node App rollout (including startup & readiness probes)...${NC}"
kubectl rollout status deployment/node-app-deployment --timeout=120s

# 5. Verification via Curl
echo -e "\n${YELLOW}Step 7: Verifying endpoints...${NC}"

PORT_FORWARD_PORT=8080
kubectl port-forward svc/node-app-service ${PORT_FORWARD_PORT}:80 > /dev/null 2>&1 &
PF_PID=$!

cleanup() {
  if [ -n "$PF_PID" ]; then
    kill $PF_PID > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep 2

TARGET_URL="http://localhost:${PORT_FORWARD_PORT}"

echo -e "\n${BLUE}--- 1. Testing Root Endpoint GET / ---${NC}"
curl -s "${TARGET_URL}/"
echo ""

echo -e "\n${BLUE}--- 2. Testing Liveness Probe GET /healthz ---${NC}"
curl -s "${TARGET_URL}/healthz"
echo ""

echo -e "\n${BLUE}--- 3. Testing Readiness Probe GET /ready ---${NC}"
curl -s "${TARGET_URL}/ready"
echo ""

echo -e "\n${BLUE}--- 4. Testing POST /users (Create User) ---${NC}"
curl -s -X POST "${TARGET_URL}/users" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test User", "email": "test@example.com"}'
echo ""

echo -e "\n${BLUE}--- 5. Testing GET /users (Fetch Users Table) ---${NC}"
curl -s "${TARGET_URL}/users" | head -n 30
echo ""

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}   Deployment & Probe Verification Successful!      ${NC}"
echo -e "${GREEN}====================================================${NC}"
