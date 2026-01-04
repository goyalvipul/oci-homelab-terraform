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

## usage

### oci

#### account

1. **Create an account** \
    Sign up for an Oracle Cloud account [here][oci]. You will need to provide credit card details for verification
    (Oracle will charge and immediately reverse a $100 fee).

2. **Upgrade to PAYG** \
    Convert your account to *Pay As You Go* (PAYG) as described [here][payg]. You won't be charged as long as you stay
    within the *Free Tier* [limits][afr].

3. **Set Governance Rules** \
    Optionally, set *Governance Rules* to enforce limits on main resources. See this [Reddit post][gov] for guidance.

#### debian

Since OCI doesn't offer any rolling-release Linux distro image, I've decided to use **Debian Sid**. Latest image is
always available [here][deb].

QCOW2 images can be easily imported to OCI by uploading them to *Object Storage* - for a step by step guide, check out
the [docs][imp].

### terraform

1. Clone the repository and prepare configuration file:
    ```sh
    git clone https://github.com/goyalvipul/oci-homelab-terraform.git
    cd oci-homelab-terraform
    cp terraform.tfvars.example terraform.tfvars
    ```

2. Edit and customize `terraform.tfvars` file.

    Start with `oci_connection` block - fill it accordingly to the official [instruction][api].

3. Initialize Terraform environment:
    ```sh
    terraform init
    ```

4. Create and review a plan:
    ```sh
    terraform plan -out=oci_homelab.tfplan
    ```

5. Build infrastructure by applying the plan:
    ```sh
    terraform apply oci_homelab.tfplan
    ```

[afr]: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm
[w2w]: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/private-net/warp-to-warp/
[wsh]: https://github.com/rany2/warp.sh
[oci]: https://oracle.com/cloud/free
[payg]: https://docs.oracle.com/en-us/iaas/Content/Billing/Tasks/changingpaymentmethod.htm#To_upgrade_to_PayasYouGo
[gov]: https://www.reddit.com/r/oraclecloud/comments/18s4f9t/using_governance_to_stay_within_free_limits
[deb]: https://cloud.debian.org/cdimage/cloud/sid/daily/latest/debian-sid-genericcloud-arm64-daily.qcow2
[imp]: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/importingcustomimagelinux.htm
[api]: https://docs.oracle.com/en-us/iaas/Content/terraform/configuring.htm#api-key-auth