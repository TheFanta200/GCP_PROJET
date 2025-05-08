# Configuration du provider Google Cloud
provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "ID du projet GCP"
  default     = "high-sunlight-458709-i9"
  type        = string
}

variable "region" {
  description = "Région GCP"
  default     = "europe-west9"
  type        = string
}

variable "zone" {
  description = "Zone GCP"
  default     = "europe-west9-b" # Change to a different zone
  type        = string
}

# Création du VPC
resource "google_compute_network" "vpc" {
  name                    = "vpc-secure-network"
  auto_create_subnetworks = false
}

# Création du sous-réseau public
resource "google_compute_subnetwork" "public_subnet" {
  name          = "public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Création du sous-réseau privé
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "private-subnet"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  # Nouveaux blocs ajoutés pour GKE
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.10.0.0/16" # Plage pour les Pods
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.20.0.0/20" # Plage pour les Services
  }
}


# Création du routeur Cloud pour la NAT Gateway
resource "google_compute_router" "router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Configuration de la NAT Gateway
resource "google_compute_router_nat" "nat_gateway" {
  name                               = "nat-gateway"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Règle de pare-feu pour autoriser SSH via IAP
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Plage d'adresses IP pour Identity-Aware Proxy
  source_ranges = ["35.235.240.0/20"]
}

# Ajout d'une règle de pare-feu pour s'assurer que le port HTTP est ouvert sur la VM
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"] # Autorise le trafic HTTP depuis toutes les sources
}

# Exemple de VM dans le réseau privé
resource "google_compute_instance" "private_vm" {
  name         = "private-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    # Pas d'access_config signifie pas d'IP publique
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    echo "<h1>Bienvenue sur Nginx dans le réseau privé</h1>" > /var/www/html/index.html
    systemctl restart nginx
  EOT
}

# Exemple de VM dans le réseau public
resource "google_compute_instance" "public_vm" {
  name         = "public-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.id

    # Configuration d'accès pour attribuer une IP publique
    access_config {
      # Aucun paramètre nécessaire pour une IP éphémère
    }
  }
}

# Règle de pare-feu pour autoriser le trafic HTTP vers la VM privée
resource "google_compute_firewall" "allow_http_private" {
  name    = "allow-http-private"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Ajout d'une règle de pare-feu pour autoriser le trafic provenant des plages IP du Load Balancer
resource "google_compute_firewall" "allow_lb_to_private" {
  name    = "allow-lb-to-private"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # Plages IP des Load Balancers GCP
}

# Configuration d'un Load Balancer pour publier la page web de la VM privée
resource "google_compute_global_address" "lb_ip" {
  name = "private-vm-lb-ip"
}

resource "google_compute_backend_service" "private_vm_backend" {
  name          = "private-vm-backend"
  health_checks = [google_compute_health_check.http_check.self_link]
  backend {
    group = google_compute_instance_group.private_vm_group.self_link
  }
}

resource "google_compute_url_map" "private_vm_url_map" {
  name            = "private-vm-url-map"
  default_service = google_compute_backend_service.private_vm_backend.self_link
}

resource "google_compute_target_http_proxy" "private_vm_http_proxy" {
  name    = "private-vm-http-proxy"
  url_map = google_compute_url_map.private_vm_url_map.self_link
}

resource "google_compute_global_forwarding_rule" "private_vm_forwarding_rule" {
  name        = "private-vm-forwarding-rule"
  ip_address  = google_compute_global_address.lb_ip.address
  ip_protocol = "TCP"
  port_range  = "80"
  target      = google_compute_target_http_proxy.private_vm_http_proxy.self_link
}

resource "google_compute_health_check" "http_check" {
  name = "http-check"

  http_health_check {
    request_path = "/"
    port         = 80
  }
}

resource "google_compute_instance_group" "private_vm_group" {
  name      = "private-vm-group"
  zone      = var.zone
  instances = [google_compute_instance.private_vm.self_link]
  named_port {
    name = "http"
    port = 80
  }
}

# Outputs
output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "public_subnet_name" {
  value = google_compute_subnetwork.public_subnet.name
}

output "private_subnet_name" {
  value = google_compute_subnetwork.private_subnet.name
}

output "nat_gateway_name" {
  value = google_compute_router_nat.nat_gateway.name
}

output "public_vm_internal_ip" {
  value = google_compute_instance.public_vm.network_interface[0].network_ip
}

output "public_vm_external_ip" {
  value = google_compute_instance.public_vm.network_interface[0].access_config[0].nat_ip
}

output "private_vm_internal_ip" {
  value = google_compute_instance.private_vm.network_interface[0].network_ip
}


# Création de la passerelle VPN cible
resource "google_compute_address" "vpn_static_ip" {
  name   = "ipsecdatacenter-ip"
  region = "europe-west9"
}
# Création de la passerelle VPN
resource "google_compute_vpn_gateway" "ipsecdatacenter" {
  name        = "ipsecdatacenter"
  description = "VPN Réseau privé"
  network     = google_compute_network.vpc.id
  region      = "europe-west9"
}

# Règles de transfert pour la passerelle VPN
resource "google_compute_forwarding_rule" "ipsecdatacenter_rule_esp" {
  name        = "ipsecdatacenter-rule-esp"
  region      = "europe-west9"
  ip_protocol = "ESP"
  ip_address  = google_compute_address.vpn_static_ip.address
  target      = google_compute_vpn_gateway.ipsecdatacenter.id
}

resource "google_compute_forwarding_rule" "ipsecdatacenter_rule_udp500" {
  name        = "ipsecdatacenter-rule-udp500"
  region      = "europe-west9"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.vpn_static_ip.address
  target      = google_compute_vpn_gateway.ipsecdatacenter.id
}

resource "google_compute_forwarding_rule" "ipsecdatacenter_rule_udp4500" {
  name        = "ipsecdatacenter-rule-udp4500"
  region      = "europe-west9"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.vpn_static_ip.address
  target      = google_compute_vpn_gateway.ipsecdatacenter.id
}


# Création du tunnel VPN
# Remplacez les valeurs ci-dessous par celles de votre configuration
# Assurez-vous que l'adresse IP distante et le secret partagé sont corrects
resource "google_compute_vpn_tunnel" "phasedeux" {
  name                   = "phasedeux"
  region                 = "europe-west9"
  peer_ip                = "82.66.171.71"
  shared_secret          = "slI/n3ICuP21IFu89rDE7P/EUly5oMDq"
  ike_version            = 2
  local_traffic_selector = ["10.0.2.0/24"]
  remote_traffic_selector = [
    "192.168.10.0/24",
    "192.168.20.0/24",
    "192.168.30.0/24",
    "192.168.40.0/24",
    "192.168.50.0/24",
    "192.168.60.0/24"
  ]
  target_vpn_gateway = google_compute_vpn_gateway.ipsecdatacenter.id

  depends_on = [
    google_compute_forwarding_rule.ipsecdatacenter_rule_esp,
    google_compute_forwarding_rule.ipsecdatacenter_rule_udp500,
    google_compute_forwarding_rule.ipsecdatacenter_rule_udp4500
  ]
}


# Création des routes pour le tunnel VPN
resource "google_compute_route" "phasedeux_route_1" {
  name                = "phasedeux-route-1"
  network             = google_compute_network.vpc.name
  priority            = 1000
  dest_range          = "192.168.10.0/24"
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.phasedeux.self_link
}

resource "google_compute_route" "phasedeux_route_2" {
  name                = "phasedeux-route-2"
  network             = google_compute_network.vpc.name
  priority            = 1000
  dest_range          = "192.168.20.0/24"
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.phasedeux.self_link
}

resource "google_compute_route" "phasedeux_route_3" {
  name                = "phasedeux-route-3"
  network             = google_compute_network.vpc.name
  priority            = 1000
  dest_range          = "192.168.30.0/24"
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.phasedeux.self_link
}

resource "google_compute_route" "phasedeux_route_4" {
  name                = "phasedeux-route-4"
  network             = google_compute_network.vpc.name
  priority            = 1000
  dest_range          = "192.168.40.0/24"
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.phasedeux.self_link
}

resource "google_compute_route" "phasedeux_route_5" {
  name                = "phasedeux-route-5"
  network             = google_compute_network.vpc.name
  priority            = 1000
  dest_range          = "192.168.50.0/24"
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.phasedeux.self_link
}
resource "google_compute_route" "phasedeux_route_6" {
  name                = "phasedeux-route-6"
  network             = google_compute_network.vpc.name
  priority            = 1000
  dest_range          = "192.168.60.0/24"
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.phasedeux.self_link
}

# Règle de pare-feu pour autoriser le ping (ICMP) à travers le VPN
resource "google_compute_firewall" "allow_icmp_vpn" {
  name    = "allow-icmp-vpn"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  # Source ranges correspondant aux plages d'adresses IP distantes du VPN
  source_ranges = [
    "192.168.10.0/24",
    "192.168.20.0/24",
    "192.168.30.0/24",
    "192.168.40.0/24",
    "192.168.50.0/24",
    "192.168.60.0/24"
  ]
}

# Outputs pour le VPN
output "vpn_gateway_name" {
  value = google_compute_vpn_gateway.ipsecdatacenter.name
}

output "vpn_tunnel_name" {
  value = google_compute_vpn_tunnel.phasedeux.name
}

# Cluster GKE privé
resource "google_container_cluster" "private_gke" {
  name       = "private-gke-cluster"
  location   = var.region # Use region instead of a specific zone
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.private_subnet.name

  # Configuration IP
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Configuration privée
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.16.0.32/28"
  }

  # Autorisation d'accès à l'API
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "192.168.0.0/16"
      display_name = "reserved-network-access"
    }
  }

  # Activer le mode Autopilot
  enable_autopilot = true

  deletion_protection = false
}