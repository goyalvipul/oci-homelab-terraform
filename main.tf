terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "6.27.0"
    }
  }

  backend "local" {
    path = "oci_homelab.tfstate"
  }
}

provider "oci" {
  tenancy_ocid     = var.oci_connection.tenancy_ocid
  user_ocid        = var.oci_connection.user_ocid
  fingerprint      = var.oci_connection.fingerprint
  private_key_path = var.oci_connection.private_key_path
  region           = var.oci_connection.region
}

resource "oci_identity_compartment" "identity" {
  compartment_id = var.oci_connection.tenancy_ocid
  name           = var.general.compartment_name
  description    = "Compartment for self-hosted infrastructure"
}

resource "oci_core_vcn" "main" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "Main VCN"
  cidr_blocks    = [var.general.main_network_cidr]
  dns_label      = "mainvcn"
}

resource "oci_core_default_security_list" "only_egress" {
  manage_default_resource_id = oci_core_vcn.main.default_security_list_id
  display_name               = "Only Egress Traffic"
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    description = "Allow all Egress traffic"
  }
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "Service Gateway"
  vcn_id         = oci_core_vcn.main.id
  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_public_ip" "nat_gateway_public_ip" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "NAT Gateway"
  lifetime       = "RESERVED"
}

output "nat_gateway_public_ip" {
  value = oci_core_public_ip.nat_gateway_public_ip.ip_address
}

resource "oci_core_nat_gateway" "nat_gateway" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "NAT Gateway"
  vcn_id         = oci_core_vcn.main.id
  public_ip_id   = oci_core_public_ip.nat_gateway_public_ip.id
}

resource "oci_core_route_table" "private" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "Private Route Table"
  vcn_id         = oci_core_vcn.main.id

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
    description       = "OCI Services traffic through Service Gateway"
  }
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat_gateway.id
    description       = "Internet traffic through NAT Gateway"
  }
}

resource "oci_core_subnet" "private" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "Private Subnet"
  vcn_id         = oci_core_vcn.main.id
  route_table_id = oci_core_route_table.private.id
  cidr_block     = var.general.private_subnet_cidr
  dns_label      = "prvsubnet"

  prohibit_internet_ingress  = true
  prohibit_public_ip_on_vnic = true
}

resource "oci_identity_customer_secret_key" "s3_credentials" {
  user_id      = var.oci_connection.user_ocid
  display_name = "Credentials for S3 access"
}

data "oci_objectstorage_namespace" "s3_namespace" {
  compartment_id = oci_identity_compartment.identity.id
}

resource "oci_objectstorage_bucket" "s3_bucket" {
  compartment_id = oci_identity_compartment.identity.id
  namespace      = data.oci_objectstorage_namespace.s3_namespace.namespace
  name           = var.general.bucket_name
  storage_tier   = "Standard"
  access_type    = "NoPublicAccess"
}

locals {
  cloud_config = <<EOF
#cloud-config
write_files:
  - path: /etc/default/grub.d/99-apparmor.cfg
    content: |
      GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=0"
  - path: /etc/sysctl.d/99-sysctl.conf
    content: |
      vm.max_map_count = 1048576
      fs.file-max = 1048576
      net.ipv4.ip_forward = 1
      net.ipv4.conf.all.src_valid_mark = 1
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
  - path: /etc/docker/daemon.json
    content: |
      {
        "ip": "127.0.0.1",
        "experimental": true,
        "live-restore": true,
        "max-concurrent-downloads": 25,
        "max-concurrent-uploads": 25,
        "storage-driver": "overlay2"
      }
  - path: /etc/environment
    content: |
      AWS_ACCESS_KEY_ID="${oci_identity_customer_secret_key.s3_credentials.id}"
      AWS_SECRET_ACCESS_KEY="${oci_identity_customer_secret_key.s3_credentials.key}"
      AWS_REGION="${var.oci_connection.region}"
      S3_ENDPOINT_URL="https://${data.oci_objectstorage_namespace.s3_namespace.namespace}.compat.objectstorage.${var.oci_connection.region}.oraclecloud.com"
      S3_BUCKET="${oci_objectstorage_bucket.s3_bucket.name}"
    append: true
%{for ifname, config in var.vm.os.wg_config~}
  - path: /etc/wireguard/${trimspace(ifname)}.conf
    content: |
      ${indent(6, trimspace(config))}
%{for svc in ["ssh", "docker"]~}
  - path: /etc/systemd/system/${svc}.service.d/wg-${trimspace(ifname)}.conf
    content: |
      [Unit]
      After=wg-quick@${trimspace(ifname)}.service
      Requires=sys-devices-virtual-net-${trimspace(ifname)}.device
%{endfor~}
%{endfor~}
  - path: /tmp/run.sh
    content: |
      #!/bin/bash
      set -exo pipefail

      update-grub
      sed -i '/PermitRootLogin/d;/PasswordAuthentication/d' /etc/ssh/sshd_config
%{if length(var.vm.os.force_dns) > 0~}
      systemctl disable --now systemd-resolved.service
      rm -f /etc/resolv.conf
      echo -e "%{for addr in var.vm.os.force_dns~}nameserver ${addr}\n%{endfor~}" > /etc/resolv.conf
      ln --symbolic /bin/true /usr/local/bin/resolvconf
%{endif~}
      apt-get install -y --no-install-recommends --no-install-suggests jq git htop wireguard-tools net-tools docker-ce docker-compose-plugin docker-buildx-plugin
      apt-get autoremove -y --purge
      curl --location "$(curl --location "https://api.github.com/repos/peak/s5cmd/releases/latest" | jq -r '.assets[] | select(.name? | match("_Linux-arm64.tar.gz$")) | .browser_download_url')" | tar --extract --gzip --file=- --directory="/usr/local/bin" s5cmd
      curl --location "$(curl --location "https://api.github.com/repos/bcicen/ctop/releases/latest" | jq -r '.assets[] | select(.name? | match("-linux-arm64$")) | .browser_download_url')" -o /usr/local/bin/ctop
      chmod -R +x /usr/local/bin
      systemctl enable docker.service %{for ifname, _ in var.vm.os.wg_config~}wg-quick@${trimspace(ifname)}.service %{endfor~}

apt:
  sources:
    docker.list:
      source: deb [arch=arm64] https://download.docker.com/linux/debian ${var.vm.os.debian_version} stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

package_update: true
package_upgrade: true
package_reboot_if_required: false
runcmd:
  - bash /tmp/run.sh

groups:
  - docker
users:
  - name: ${var.vm.os.username}
    no_user_group: true
    primary_group: users
    groups:
      - sudo
      - docker
    shell: /bin/bash
    ssh_authorized_keys:
%{for key in var.vm.ssh_public_keys~}
      - '${trimspace(key)}'
%{endfor~}
%{if var.vm.os.password != ""~}
    plain_text_passwd: ${var.vm.os.password}
    lock_passwd: false
%{endif~}

power_state:
  mode: reboot
    EOF
}

output "cloud-config" {
  value = local.cloud_config
}

data "oci_core_images" "debian_image" {
  compartment_id = var.oci_connection.tenancy_ocid
  display_name   = var.vm.image_name
}

data "oci_identity_availability_domain" "ad" {
  compartment_id = var.oci_connection.tenancy_ocid
  ad_number      = var.vm.availability_domain
}

resource "oci_core_instance" "infra_vm" {
  compartment_id       = oci_identity_compartment.identity.id
  display_name         = "${var.vm.name} VM"
  availability_domain  = data.oci_identity_availability_domain.ad.name
  preserve_boot_volume = false

  shape = var.vm.shape
  shape_config {
    ocpus         = var.vm.cpus
    memory_in_gbs = var.vm.mem_size
  }
  source_details {
    source_id               = data.oci_core_images.debian_image.images[0].id
    source_type             = "image"
    boot_volume_size_in_gbs = var.vm.disk_size
  }
  launch_options {
    firmware         = "UEFI_64"
    boot_volume_type = "PARAVIRTUALIZED"
    network_type     = "PARAVIRTUALIZED"
  }
  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    display_name     = "vnic0"
    hostname_label   = var.vm.os.hostname
    private_ip       = var.vm.private_ip
    assign_public_ip = false
  }
  agent_config {
    is_management_disabled = true
    is_monitoring_disabled = true
  }
  metadata = {
    ssh_authorized_keys = join("\n", [for key in var.vm.ssh_public_keys : trimspace(key)])
    user_data           = base64encode(local.cloud_config)
  }
  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "oci_core_volume_backup_policy" "backup" {
  compartment_id = oci_identity_compartment.identity.id
  display_name   = "${var.vm.name} Backups"

  schedules {
    backup_type       = "INCREMENTAL"
    period            = "ONE_DAY"
    retention_seconds = var.vm.daily_backups * 24 * 60 * 60
    offset_type       = "STRUCTURED"
    hour_of_day       = 1
    time_zone         = "UTC"
  }
  schedules {
    backup_type       = "FULL"
    period            = "ONE_WEEK"
    retention_seconds = var.vm.weekly_backups * 7 * 24 * 60 * 60
    offset_type       = "STRUCTURED"
    day_of_week       = "SUNDAY"
    hour_of_day       = 4
    time_zone         = "UTC"
  }
}

resource "oci_core_volume_backup_policy_assignment" "backup" {
  asset_id  = oci_core_instance.infra_vm.boot_volume_id
  policy_id = oci_core_volume_backup_policy.backup.id
}
