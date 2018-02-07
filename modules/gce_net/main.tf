variable "bastion_config" {}
variable "bastion_image" {}

variable "bastion_zones" {
  default = ["b", "f"]
}

variable "deny_target_ip_ranges" {
  type    = "list"
  default = []
}

variable "env" {}
variable "github_users" {}
variable "index" {}
variable "nat_config" {}
variable "nat_image" {}
variable "nat_machine_type" {}

variable "nat_zones" {
  default = ["a", "b", "c", "f"]
}

variable "project" {}

variable "region" {
  default = "us-central1"
}

variable "syslog_address" {}
variable "travisci_net_external_zone_id" {}

variable "public_subnet_cidr_range" {
  default = "10.10.0.0/22"
}

variable "workers_subnet_cidr_range" {
  default = "10.10.4.0/22"
}

variable "jobs_org_subnet_cidr_range" {
  default = "10.20.0.0/16"
}

variable "jobs_com_subnet_cidr_range" {
  default = "10.30.0.0/16"
}

variable "build_com_subnet_cidr_range" {
  default = "10.10.12.0/22"
}

variable "build_org_subnet_cidr_range" {
  default = "10.10.8.0/22"
}

resource "google_compute_network" "main" {
  name                    = "main"
  project                 = "${var.project}"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "public" {
  name          = "public"
  ip_cidr_range = "${var.public_subnet_cidr_range}"
  network       = "${google_compute_network.main.self_link}"
  region        = "${var.region}"
  project       = "${var.project}"
}

resource "google_compute_subnetwork" "workers" {
  name          = "workers"
  ip_cidr_range = "${var.workers_subnet_cidr_range}"
  network       = "${google_compute_network.main.self_link}"
  region        = "${var.region}"
  project       = "${var.project}"
}

resource "google_compute_subnetwork" "jobs_org" {
  name          = "jobs-org"
  ip_cidr_range = "${var.jobs_org_subnet_cidr_range}"
  network       = "${google_compute_network.main.self_link}"
  region        = "${var.region}"
  project       = "${var.project}"
}

resource "google_compute_subnetwork" "jobs_com" {
  name          = "jobs-com"
  ip_cidr_range = "${var.jobs_com_subnet_cidr_range}"
  network       = "${google_compute_network.main.self_link}"
  region        = "${var.region}"

  project = "${var.project}"
}

resource "google_compute_firewall" "allow_main_ssh" {
  name          = "allow-main-ssh"
  network       = "${google_compute_network.main.name}"
  source_ranges = ["87.142.116.219"]
  priority      = 1000

  allow {
    protocol = "tcp"
    ports    = [22]
  }
}

resource "google_compute_firewall" "allow_public_ssh" {
  name          = "allow-public-ssh"
  network       = "${google_compute_network.main.name}"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]

  project = "${var.project}"

  allow {
    protocol = "tcp"
    ports    = [22]
  }
}

resource "google_compute_firewall" "allow_public_icmp" {
  name          = "allow-public-icmp"
  network       = "${google_compute_network.main.name}"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nat", "bastion"]

  project = "${var.project}"

  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = "${google_compute_network.main.name}"

  source_ranges = [
    "${google_compute_subnetwork.public.ip_cidr_range}",
    "${google_compute_subnetwork.workers.ip_cidr_range}",
  ]

  project = "${var.project}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
}

resource "google_compute_firewall" "allow_jobs_nat" {
  name    = "allow-jobs-nat"
  network = "${google_compute_network.main.name}"

  source_ranges = [
    "${google_compute_subnetwork.jobs_org.ip_cidr_range}",
    "${google_compute_subnetwork.jobs_com.ip_cidr_range}",
  ]

  target_tags = ["nat"]

  project = "${var.project}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
}

resource "google_compute_firewall" "deny_target_ip" {
  name    = "deny-target-ip"
  network = "${google_compute_network.main.name}"

  direction          = "EGRESS"
  destination_ranges = ["${var.deny_target_ip_ranges}"]

  project = "${var.project}"

  # highest priority
  priority = "1000"

  deny {
    protocol = "tcp"
  }

  deny {
    protocol = "udp"
  }

  deny {
    protocol = "icmp"
  }
}

resource "google_compute_address" "nat" {
  count   = "${length(var.nat_zones)}"
  name    = "nat-${element(var.nat_zones, count.index)}"
  region  = "${var.region}"
  project = "${var.project}"
}

resource "aws_route53_record" "nat" {
  count   = "${length(var.nat_zones)}"
  zone_id = "${var.travisci_net_external_zone_id}"
  name    = "nat-${var.env}-${var.index}.gce-${var.region}-${element(var.nat_zones, count.index)}.travisci.net"
  type    = "A"
  ttl     = 5

  records = [
    "${element(google_compute_address.nat.*.address, count.index)}",
  ]
}

data "template_file" "nat_cloud_config" {
  template = "${file("${path.module}/nat-cloud-config.yml.tpl")}"

  vars {
    nat_config       = "${var.nat_config}"
    cloud_init_bash  = "${file("${path.module}/nat-cloud-init.bash")}"
    github_users_env = "export GITHUB_USERS='${var.github_users}'"
    syslog_address   = "${var.syslog_address}"
    assets           = "${path.module}/../../assets"
  }
}

resource "google_compute_instance_template" "nat" {
  count          = "${length(var.nat_zones)}"
  name           = "${var.env}-${var.index}-nat-${element(var.nat_zones, count.index)}-template-${substr(sha256(data.template_file.nat_cloud_config.rendered), 0, 7)}"
  machine_type   = "${var.nat_machine_type}"
  can_ip_forward = true
  region         = "${var.region}"
  tags           = ["nat", "${var.env}"]
  project        = "${var.project}"

  labels {
    environment = "${var.env}"
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  disk {
    auto_delete  = true
    boot         = true
    source_image = "${var.nat_image}"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.public.self_link}"

    access_config {
      nat_ip = "${element(google_compute_address.nat.*.address, count.index)}"
    }
  }

  metadata {
    "block-project-ssh-keys" = "true"
    "user-data"              = "${data.template_file.nat_cloud_config.rendered}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_http_health_check" "nat" {
  name                = "nat-health-check"
  request_path        = "/health-check"
  check_interval_sec  = 30
  healthy_threshold   = 1
  unhealthy_threshold = 5
}

resource "google_compute_firewall" "nat" {
  name        = "nat"
  network     = "${google_compute_network.main.name}"
  target_tags = ["nat"]
  project     = "${var.project}"

  source_ranges = [
    "209.85.152.0/22",
    "209.85.204.0/22",
    "35.191.0.0/16",
  ]

  allow {
    protocol = "tcp"
    ports    = [80]
  }
}

resource "google_compute_instance_group_manager" "nat" {
  count              = "${length(var.nat_zones)}"
  name               = "nat-${element(var.nat_zones, count.index)}"
  target_size        = 1
  base_instance_name = "nat"
  instance_template  = "${element(google_compute_instance_template.nat.*.self_link, count.index)}"
  zone               = "${var.region}-${element(var.nat_zones, count.index)}"

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = "${google_compute_http_health_check.nat.self_link}"
    initial_delay_sec = 300
  }
}

data "external" "nats_by_zone" {
  program = ["${path.module}/../../bin/gcloud-nats-by-zone"]

  query {
    zones   = "${join(",", var.nat_zones)}"
    region  = "${var.region}"
    project = "${var.project}"
  }

  depends_on = ["google_compute_instance_group_manager.nat"]
}

resource "google_compute_route" "nat" {
  count                  = "${length(var.nat_zones)}"
  name                   = "nat-${element(var.nat_zones, count.index)}"
  dest_range             = "0.0.0.0/0"
  tags                   = ["no-ip"]
  priority               = 800
  next_hop_instance_zone = "${var.region}-${element(var.nat_zones, count.index)}"
  next_hop_instance      = "${data.external.nats_by_zone.result[element(var.nat_zones, count.index)]}"
  network                = "${google_compute_network.main.self_link}"

  lifecycle {
    ignore_changes = ["next_hop_instance", "id"]
  }
}

resource "google_compute_address" "bastion" {
  count   = "${length(var.bastion_zones)}"
  name    = "bastion-${element(var.bastion_zones, count.index)}"
  region  = "${var.region}"
  project = "${var.project}"
}

resource "aws_route53_record" "bastion" {
  count   = "${length(var.bastion_zones)}"
  zone_id = "${var.travisci_net_external_zone_id}"
  name    = "bastion-${var.env}-${var.index}.gce-${var.region}-${element(var.bastion_zones, count.index)}.travisci.net"
  type    = "A"
  ttl     = 5

  records = [
    "${element(google_compute_address.bastion.*.address, count.index)}",
  ]
}

data "template_file" "bastion_cloud_config" {
  template = "${file("${path.module}/bastion-cloud-config.yml.tpl")}"

  vars {
    bastion_config   = "${var.bastion_config}"
    cloud_init_bash  = "${file("${path.module}/bastion-cloud-init.bash")}"
    github_users_env = "export GITHUB_USERS='${var.github_users}'"
    syslog_address   = "${var.syslog_address}"
  }
}

resource "google_compute_instance" "bastion" {
  count        = "${length(var.bastion_zones)}"
  name         = "${var.env}-${var.index}-bastion-${element(var.bastion_zones, count.index)}"
  machine_type = "g1-small"
  zone         = "${var.region}-${element(var.bastion_zones, count.index)}"
  tags         = ["bastion", "${var.env}"]
  project      = "${var.project}"

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "${var.bastion_image}"
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.public.self_link}"

    access_config {
      nat_ip = "${element(google_compute_address.bastion.*.address, count.index)}"
    }
  }

  metadata {
    "block-project-ssh-keys" = "true"
    "user-data"              = "${data.template_file.bastion_cloud_config.rendered}"
  }
}

output "gce_subnetwork_public" {
  value = "${google_compute_subnetwork.public.self_link}"
}

output "gce_subnetwork_workers" {
  value = "${google_compute_subnetwork.workers.self_link}"
}