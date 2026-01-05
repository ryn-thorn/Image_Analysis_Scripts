These are generic image analysis scripts that I have written, collected, 
and otherwise given cobbled-together life to through much trial and error during my time 
at MUSC in the BRIDGE Lab. Versions of these scripts can be found in various studies' 
"STUDY_code" BIDS folders. These are here as a log/reference do the most basic, generic 
forms of these scripts, not modified for any particular study's analysis pipeline.

www.bridge-lab.org</br>
www.bridgelab.info</br>

<img src="https://www.bridge-lab.org/storage/329/9f17e7e8-434b-4d67-85f7-bc57bcd496cc/bridge-logo.png">

## Docker Setup

### Step 1: Install Docker
- macOS / Windows: [Download Docker Desktop](https://www.docker.com/products/docker-desktop/)  
- Linux: Install Docker Engine via your package manager (`apt`, `yum`, etc.)  

### Step 2: Check Installation
- Verify installation by running:
```bash
docker run hello-world

## Freesurfer 6.0 Docker Container

### Step 1: Download Freesurfer Docker Package

cd /path/to/freesurfer-6.0-docker
docker build -t freesurfer:6.0 .
