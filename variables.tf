variable "oci_connection" {
  type = object({
    tenancy_ocid     = string
    user_ocid        = string
    fingerprint      = string
    private_key_path = string
    region           = optional(string, "eu-frankfurt-1")
  })
}

variable "general" {
  type = object({
    compartment_name    = optional(string, "infra")
    bucket_name         = optional(string, "bucket")
    main_network_cidr   = optional(string, "172.16.0.0/16")
    private_subnet_cidr = optional(string, "172.16.0.0/24")
  })
}

variable "vm" {
  type = object({
    name                = string
    availability_domain = optional(number, 1)
    shape               = optional(string, "VM.Standard.A1.Flex")
    cpus                = optional(number, 4)
    mem_size            = optional(number, 24)
    disk_size           = optional(number, 200)
    image_name          = string
    private_ip          = optional(string, "172.16.0.2")
    ssh_public_keys     = list(string)
    os = object({
      hostname       = string
      debian_version = optional(string, "bookworm")
      username       = optional(string, "infra")
      password       = optional(string, "")
      force_dns      = optional(list(string), [])
      wg_config      = optional(map(string), {})
    })
    daily_backups  = optional(number, 3)
    weekly_backups = optional(number, 2)
  })
}
