
variable "credentials_file" { 
  default = "/home/eli6679/cis-91-362518-3075db6e3e49.json" 
}

variable "project" {
  default = "cis-91-362518"
}

variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-c"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  region  = var.region
  zone    = var.zone 
  project = var.project
}

resource "google_compute_network" "vpc_network" {
  name = "dokuwiki-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "dokuwiki"
  machine_type = "e2-micro"
  allow_stopping_for_update = true


  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
  attached_disk {
    source = google_compute_disk.data.self_link
    device_name = "data"
  }

  service_account {
    email  = google_service_account.dokuwiki-service-account.email
    scopes = ["cloud-platform"]
  }

}

resource "google_service_account" "dokuwiki-service-account" {
  account_id   = "dokuwiki-service-account"
  display_name = "dokuwiki-service-account"
  description = "Service account for dokuwiki"
}

resource "google_project_iam_member" "project_member" {
  role = "roles/compute.viewer"
  member = "serviceAccount:${google_service_account.dokuwiki-service-account.email}"
}



resource "google_compute_firewall" "default-firewall" {
  name = "dokuwiki-firewall"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports = ["22", "80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

output "external-ip" {
  value = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}

resource "google_compute_disk" "data" {
  name  = "data"
  type  = "pd-ssd"
  labels = {
    environment = "dev"
  }
  size = "16"
}