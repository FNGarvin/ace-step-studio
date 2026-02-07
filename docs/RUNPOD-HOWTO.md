# Deploying ACE-Step Studio on RunPod

This guide explains how to deploy ACE-Step Studio on a RunPod GPU instance using the Docker image.

## Prerequisites

-   A [RunPod](https://runpod.io) account.
-   Credits in your RunPod balance.

## deployment Steps

1.  **Select a Template**:
    -   Go to **Templates** in RunPod.
    -   Click **New Template**.
    -   **Name**: ACE-Step Studio
    -   **Image Name**: `fngarvin/ace-step-studio:latest` (or your Docker Hub image)
    -   **Container Disk**: 20 GB (Recommended)
    -   **Volume Disk**: 50 GB (Recommended for models)
    -   **Volume Mount Path**: `/workspace/ACE-Step-1.5/checkpoints` (Crucial for persisting models!)
    -   **Exposed Ports**: `8788, 5175, 8080, 22`

2.  **Deploy a Pod**:
    -   Select **Secure Cloud** or **Community Cloud**.
    -   Choose a GPU (e.g., RTX 3090 or RTX 4090).
    -   Select the **ACE-Step Studio** template you created.
    -   Click **Deploy**.

3.  **Access the Application**:
    -   Once the pod is running, click **Connect**.
    -   You will see mapped ports for **TCP**.
    -   Find the public IP and port mapped to `5175` (Frontend).
    -   Open `http://<public-ip>:<mapped-port-5175>` in your browser.

4.  **Download Models (First Run Only)**:
    -   **Important**: The container does **not** come with pre-downloaded models to keep the image small.
    -   Open the **Settings** (gear icon) in the top right of the ACE-Step Studio UI.
    -   Locate the **Model Selection** list.
    -   Click the **Red Status Light** next to a model (e.g., "Turbo DiT") to start the download.
    -   **Wait**: Large models can take several minutes. You can monitor the progress by checking the container logs in RunPod console (`Logs` button).
    -   Once the light turns **Green**, the model is loaded and ready.

5.  **Generate a Song**:
    -   Enter a prompt (e.g., "Upbeat jazz funk").
    -   Click **Generate**.

## Persistence

By mounting `/workspace/ACE-Step-1.5/checkpoints` to the persistent volume, your downloaded models will survive pod restarts.

## SSH Access

-   **Port**: 22 (mapped to a random port by RunPod)
-   **User**: `root`
-   **Password**: There is no password. Use your public SSH key added to RunPod settings.

## File Manager

-   Access the web-based file manager on port `8080` (mapped port).
-   Default login: `admin` / `admin` (Change this immediately if exposed publicly!).
