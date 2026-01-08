# oci-homelab-terraform
these are terraform scripts which you can use to setup your Oracle Cloud Interface - it will provision the best machine for you in the Free Tier

# oci-homelab-terraform

Oracle Cloud Infrastructure (OCI) has a generous free option for ARM64 based instances - 4 CPUs with 24 GB memory (and
more - for details see [Always Free Resources][afr] docs).

This repo contains Terraform plan that builds the infrastructure matching free resource limits with an emphasis
on basic security principles:
  * Instance is not exposed to the internet - stays behind NAT with only egress traffic allowed
  * Automated Wireguard client setup

The main goal for this project is an ultimate self hosted homelab setup with site-to-site VPN based on
[Cloudflare WARP-to-WARP][w2w] using vanilla Wireguard with [warp.sh][wsh]. \
At least it's what I did 😉

- LTS OS
- SSH-only access
- Private-only networking
- One-way initiated tunnel
- Zero inbound attack surface
-- This is enterprise-grade design, not homelab cosplay.

## Usage - How to use my repository

### OCI Account Creation

1. **Create an account** \
    Sign up for an Oracle Cloud account [here][oci]. You will need to provide credit card details for verification
    (Oracle will charge and immediately reverse a $100 fee).

2. **Upgrade to PAYG** \
    Convert your account to *Pay As You Go* (PAYG) as described [here][payg]. You won't be charged as long as you stay
    within the *Free Tier* [limits][afr].

3. **Set Governance Rules** \
    Optionally, set *Governance Rules* to enforce limits on main resources. See this [Reddit post][gov] for guidance.

#### Image - OS

I have selected Ubuntu over notmal Linux OS, because of ease of use as well it is the best alternative to deploy major set of services for which we are creating this instance. 

# Oracle Cloud Always Free Homelab Infrastructure

This repository contains Terraform configurations to deploy a secure, "Always Free" capable infrastructure on Oracle Cloud (OCI). It provisions a high-performance ARM64 Ubuntu VM tailored for self-hosting, complete with WireGuard VPN, Docker, and automatic backups.

## 🏗 What This Deploys

* **Compute:**
    * 1x **Ampere A1 Compute Instance** (ARM64) with 4 OCPUs and 24GB RAM.
    * OS: Ubuntu 22.04 LTS (Canonical).
* **Networking:**
    * Custom VCN (`172.16.0.0/16`) and Private Subnet (`172.16.0.0/24`).
    * **Hardened Security List:** Only allows outgoing traffic and incoming WireGuard UDP traffic (Port 51820).
    * **Service Gateway:** Secure internal access to Oracle Object Storage without traversing the public internet.
* **Storage & Backups:**
    * 100GB Boot Volume. (You can go uptill 200 GB which is FREE, but I want to keep a buffer as this can be attached anytime later)
    * **Automated Backups:** Daily and Weekly gold/bronze policy backups.
    * **Object Storage Bucket:** Created for S3-compatible app backups.
* **Software Stack (via Cloud-Init):**
    * **Docker & Docker Compose:** Pre-installed for container management.
    * **WireGuard:** Pre-configured VPN interface (`wg0`) for secure private access.
    * **Utilities:** `s5cmd` (fast S3 client), `ctop` (container monitoring), `htop`, `git`.
    * **Security:** Password login disabled, Root login disabled, SSH hardened.

## 🚀 Prerequisites

1.  **Oracle Cloud Account:** A verified account with access to the "Always Free" tier.
2.  **Terraform:** [Install Terraform](https://developer.hashicorp.com/terraform/downloads) on your local machine.
3.  **OCI API Keys:**
    * Generate an API Key pair in the Oracle Console (User Settings -> API Keys).
    * Download the private key (`.pem`) to your computer.
    * Note your Tenancy OCID, User OCID, and Fingerprint.
4.  **SSH Key Pair:** A local SSH key (`~/.ssh/id_ed25519` or similar) to access the VM.

## 🛠️ Usage Instructions

### 1. Clone & Initialize
Clone this repository and initialize Terraform:
```bash
git clone https://github.com/goyalvipul/oci-homelab-terraform.git
cd oci-homelab-terraform
terraform init
terraform plan
```
### **Part 2: 
1. Configure Variables
Copy the example variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Generate Password Hash (Optional)
If you want to set a sudo password for the user (to allow sudo access without relying solely on SSH keys), generate a SHA-512 hash locally:

```
# Run this on your local machine
python3 -c 'import crypt; print(crypt.crypt("YOUR_SECRET_PASSWORD", crypt.mksalt(crypt.METHOD_SHA512)))'
Update main.tf (under the users block) with this hash string.
```

3. Deploy
Review the plan and apply:

```
terraform plan
terraform apply
```

4. Connect
After deployment, Terraform will output the Public IP of the instance.

* WireGuard: Update your local WireGuard client with the Peer configuration matching the server keys you generated.

* SSH: Access the VM securely over the VPN (recommended) or Public IP (if configured):

```
# Via VPN (Private IP)
ssh infra@10.200.0.2
```

## 🔑 Configuration Guide: Where to Get Keys

| Variable | Where to find it? |
| :--- | :--- |
| **`tenancy_ocid`** | Oracle Console -> Profile Icon -> Tenancy: [Name] -> Copy OCID. |
| **`user_ocid`** | Oracle Console -> Profile Icon -> User Settings -> Copy OCID. |
| **`fingerprint`** | Oracle Console -> User Settings -> API Keys (It appears after you add a key). |
| **`private_key_path`** | The absolute path on your computer where you saved the `.pem` file from Oracle. |
| **`compartment_ocid`** | Oracle Console -> Identity & Security -> Compartments -> Copy OCID (usually same as Tenancy for root). |
| **`ssh_public_keys`** | Run `cat ~/.ssh/id_ed25519.pub` on your local machine. |
| **`wg_config` Keys** | Run `wg genkey \| tee privatekey \| wg pubkey > publickey` locally to generate a pair. Use the server private key in Terraform and the server public key in your client app. |

📤 Outputs
vm_public_ip: The IPv4 address of the created instance.

cloud-config: The raw cloud-init YAML used to bootstrap the server (useful for debugging).

⚠️ Security Notes
SSH Port 22: By default, this setup expects you to use WireGuard to access SSH. Ensure your Security List allows UDP 51820.

Secrets: Never commit terraform.tfvars or your .pem key files to GitHub. Use .gitignore to exclude them.


---

### **Part 3: Configuration & Keys Guide**

Here is a quick reference for Step 5 of your request ("Where to add/modify keys").

**1. OCI Connection Keys**
* **Location:** `terraform.tfvars` (top block).
* **Source:** These come directly from the Oracle Cloud Console under **User Settings > API Keys**. You must upload a public key there and keep the private key on your laptop.

**2. SSH Public Key**
* **Location:** `terraform.tfvars` -> `vm` -> `ssh_public_keys`.
* **Source:** Your local computer. Run `cat ~/.ssh/id_ed25519.pub`. This allows you to log in initially.

**3. WireGuard Keys (The VPN)**
* **Location:** `terraform.tfvars` -> `wg_config`.
* **Source:** You must generate these yourself.
    * **Server Private Key:** Put this in the `terraform.tfvars` file under `PrivateKey`.
    * **Client Public Key:** Put this in the `terraform.tfvars` file under `[Peer] PublicKey`.
    * *Note:* You keep the *Client Private Key* on your laptop/phone app; it never goes into Terraform.

**4. User Password Hash**
* **Location:** `main.tf` -> `users` -> `passwd`.
* **Source:** Generated via Python command (included in README). This is required if you want to use `sudo` commands that ask for a password.
