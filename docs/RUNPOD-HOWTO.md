# ☁️ RunPod Deployment Guide: ACE-Step Studio

Follow this guide to deploy ACE-Step Studio on RunPod for high-performance cloud processing with data-center network speeds.

---

### 1. Configure GPU & CUDA Version
Choose a GPU and any parameters you prefer (e.g. location, network, etc.). 
> [!IMPORTANT]
> Ensure you select **CUDA 12.8 and/or higher** in the instance settings to ensure compatibility with the current PyTorch engines and the 5Hz LM model.

### 2. Select the Template
Search for and select the **ace-step-studio** template. The default parameters should be optimal for most use cases, but feel free to adjust them as desired.

Verify that the template, pricing summary, and Pod summary are all to your liking. If so, click the blue **Deploy On-Demand** button at the bottom of the page.

### 3. (Optional) Monitor Deployment
While the pod initializes, you can monitor the progress by clicking the **Logs** tab. This is where you can see model downloads and any potential initialization errors. 
> [!NOTE]
> The model files required are quite large, so if the tool must download them it will take a while.  You can monitor the progress in the logs.

### 4. Access the Application
Once the status is "Running," click the **Connect** button. You will see two primary HTTP services:
*   **Port 5175:** The ACE-Step Studio Web App (Frontend).
*   **Port 8788:** The Backend API (you shouldn't need to access this directly).
*   **Port 8080:** The File Manager (A web-based file browser with full upload and download capabilities).

### 5. Using the App
The ACE-Step Studio interface allows you to generate music from prompts and lyrics exactly as you would locally.
> [!TIP]
> If you go into the settings menu, you can preload the models of your choice by clicking on the small colored circles next to the model names.

### 6. Managing Datasets & Models
Use the integrated **File Manager** to browse the workspace, download your generated songs, or manage your model checkpoints.
*   **Songs**: `/workspace/data/generation` is where your generated songs are stored.  You can download them individually or the entire directory as a zip file.

---
<div align="center">
  <b>Managed Deployment via RunPod</b>
</div>
