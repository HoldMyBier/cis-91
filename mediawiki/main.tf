
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
  name = "cis91-network"
}

resource "google_compute_instance" "webservers" {
  count        = 3
  name         = "web${count.index}"
  machine_type = "e2-micro"
  tags         = ["web"]
  labels       = {
    name: "web${count.index}"
  }

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

}

resource "google_compute_instance" "vm_instance" {
  name         = "db"
  machine_type = "e2-micro"
  tags         = ["db"]

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
  
}

resource "google_compute_firewall" "default-firewall" {
  name = "default-firewall"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports = ["22", "80"]
  }
  
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "rules" {
  project     = "cis-91-362518"
  name        = "db-firewall-rule"
  network     = "cis91-network"
  description = "Creates firewall rule targeting tagged instances"

  allow {
    protocol  = "tcp"
    ports     = ["5432"]
  }

  source_tags = ["web"]
  target_tags = ["db"]
}

resource "google_compute_firewall" "rule22" {
  project     = "cis-91-362518"
  name        = "db22-firewall-rule"
  network     = "cis91-network"
  description = "Allows port 22 all hosts"

  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }
  target_tags = []
}

resource "google_compute_firewall" "rule80" {
  project     = "cis-91-362518"
  name        = "db80-firewall-rule"
  network     = "cis91-network"
  description = "Allows port 80 to web"

  allow {
    protocol  = "tcp"
    ports     = ["80"]
  }
  target_tags = ["web"]

}

resource "google_compute_disk" "data" {
  name  = "data"
  type  = "pd-ssd"
  labels = {
    environment = "dev"
  }
  size = "16"
}

output "external-ip" {
  value = google_compute_instance.webservers[*].network_interface[0].access_config[0].nat_ip
}


resource "google_compute_health_check" "webservers" {
  name = "webserver-health-check"

  timeout_sec        = 1
  check_interval_sec = 1

  http_health_check {
    request_path = "/health.html"
    port = 80
  }
}


resource "google_compute_instance_group" "webservers" {
  name        = "cis91-webservers"
  description = "Webserver instance group"

  instances = google_compute_instance.webservers[*].self_link

  named_port {
    name = "http"
    port = "80"
  }
}


resource "google_compute_backend_service" "webservice" {
  name      = "web-service"
  port_name = "http"
  protocol  = "HTTP"

  backend {
    group = google_compute_instance_group.webservers.id
  }

  health_checks = [
    google_compute_health_check.webservers.id
  ]
}

resource "google_compute_url_map" "default" {
  name            = "my-site"
  default_service = google_compute_backend_service.webservice.id
}

resource "google_compute_target_http_proxy" "default" {
  name     = "web-proxy"
  url_map  = google_compute_url_map.default.id
}

resource "google_compute_global_address" "default" {
  name = "external-address"
}


resource "google_compute_global_forwarding_rule" "default" {
  name                  = "forward-application"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.address
}

output "lb-ip" {
  value = google_compute_global_address.default.address
}