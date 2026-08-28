# Basic Node.js App Deployment

This guide will help you build a Docker image for the basic Node.js app located in the `node-app` directory.

## Prerequisites

- Docker installed on your machine
- Basic knowledge of Docker and Node.js

## Steps to Build the Docker Image

1. **Navigate to the `node-app` directory:**

    ```sh
    cd node-app
    ```

2. **Build the Docker image:**

    ```sh
    docker build -t node-app:1.0 .
    ```

    This command will use the `Dockerfile` present in the `node-app` directory to build the Docker image and tag it as `node-app`.

3. **Verify the Docker image:**

    ```sh
    docker images
    ```

    You should see `node-app` listed in the output.

## Running the Docker Container

To run the Docker container from the image you just built:

```sh
docker run -p 3000:3000 node-app:1.0
```

This will start the Node.js app and map port 3000 of the container to port 3000 on your host machine.

## Deploying to Kubernetes

To deploy the Node.js app to a Kubernetes cluster, follow these steps:

1. **Navigate to the `k8s` directory:**

    ```sh
    cd k8s
    ```


2. **Apply the Deployment:**

    ```sh
    kubectl apply -f deployment.yaml
    ```

    This command will create the deployment in your Kubernetes cluster.

3. **Create Service resource:**

    Apply the service configuration:

    ```sh
    kubectl apply -f service.yaml
    ```

    This will expose your Node.js app via a clusterIp service.

4. **Verify the Deployment:**

    ```sh
    kubectl get deployments
    kubectl get services
    ```

    Ensure that the deployment and service are running correctly.

Your Node.js app should now be accessible through the IP provided by the ClusterIP service.

## Automated Clean Build, Deploy, and Test

An automated script [`test.sh`](file:///Users/mayanksoni/personal/github/basic-k8s-deployment/test.sh) is provided to perform cleanups, Docker builds, Kubernetes deployments, and access testing in a single step:

```sh
./test.sh
```

This script will:
1. Clean up existing deployments/services (`kubectl delete`).
2. Build the Docker image (`node-app:2.0`).
3. Deploy MySQL database and Node.js application resources.
4. Wait for both deployments to become rollout ready (`kubectl rollout status`).
5. Establish port forwarding and test HTTP endpoints using `curl`.


> You can follow the same steps to build and deploy the python flask app. Only you need to change the image referenced in your deployment.yaml file.


