terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.70.3"
    }
  }
}

provider "huaweicloud" {
    region = var.region
    access_key = var.hwc_access_key
    secret_key = var.hwc_secret_key
}

data "huaweicloud_enterprise_project" "main" {
  name = var.enterprise_project
}

locals {
  enterprise_project_id = data.huaweicloud_enterprise_project.main.id
}

data "huaweicloud_vpc" "vpc"{
    name = "vpc-prm"
}

data "huaweicloud_vpc_subnet" "net" {
    name = "subnet-K8s-ArgoCD"
}

data "huaweicloud_networking_secgroup" "sgp" {
    name = "sg-N8N"
}


resource "huaweicloud_cce_cluster" "cluster"{
    name = "cce-argocd"
    flavor_id = "cce.s1.small"
    vpc_id = data.huaweicloud_vpc.vpc.id
    subnet_id = data.huaweicloud_vpc_subnet.net.id
    container_network_type = "vpc-router"
}

# ECS instance and its data requirements

data "huaweicloud_images_image" "linux"{
    name = "Ubuntu 22.04 server 64bit"
}

resource "huaweicloud_compute_instance" "ecs" {
    name = "ecs-bastion"
    image_id = data.huaweicloud_images_image.linux.id
    flavor_id = "t6.small.1"
    security_group_ids = [data.huaweicloud_networking_secgroup.sgp.id]
    admin_pass = var.ecs_pass

    network {
      uuid = data.huaweicloud_vpc_subnet.net.id
    }
}

resource "huaweicloud_vpc_eip" "eip" {
    name = "eip-nat"
    publicip {
        type = "5_bgp"
    }

    bandwidth {
      name = "eip-nat"
      size = 100
      share_type = "PER"
      charge_mode = "traffic"
    }   
}

resource "huaweicloud_nat_gateway" "nat" {
  name        = "nat-K8s-ArgoCD"
  spec        = "1"
  vpc_id      = data.huaweicloud_vpc.vpc.id
  subnet_id   = data.huaweicloud_vpc_subnet.net.id
  enterprise_project_id = local.enterprise_project_id
}

resource "huaweicloud_nat_snat_rule" "test" {
  nat_gateway_id = huaweicloud_nat_gateway.nat.id
  floating_ip_id = huaweicloud_vpc_eip.eip.id
  subnet_id      = data.huaweicloud_vpc_subnet.net.id
}

resource "huaweicloud_nat_dnat_rule" "bastion_ssh" {
    nat_gateway_id = huaweicloud_nat_gateway.nat.id
    floating_ip_id = huaweicloud_vpc_eip.eip.id
    port_id = huaweicloud_compute_instance.ecs.network[0].port
    protocol = "tcp"
    internal_service_port = 22
    external_service_port = var.bastion_public_port
}

resource "huaweicloud_cce_node_pool" "node_pool" {
    cluster_id = huaweicloud_cce_cluster.cluster.id
    name = "argocd-pool"
    os = "Huawei Cloud EulerOS 2.0"
    flavor_id = "c7n.3xlarge.2"
    password = "senha!23"
    scall_enable = true
    min_node_count = 1
    max_node_count = 6
    scale_down_cooldown_time = 5
    priority = 1
    type = "vm"
    initial_node_count = 1


    root_volume {
        size = 50
        volumetype = "SAS"
    }

    data_volumes {
        size = 100
        volumetype = "SAS"
    }
}

data "huaweicloud_cce_addon_template" "autoscaler" {
    cluster_id = huaweicloud_cce_cluster.cluster.id
    name = "autoscaler"
    version = "1.30.19"
}

resource "huaweicloud_cce_addon" "autoscaler" {
  cluster_id    = huaweicloud_cce_cluster.cluster.id
  template_name = data.huaweicloud_cce_addon_template.autoscaler.name
  version       = data.huaweicloud_cce_addon_template.autoscaler.version
 
  values {
    basic_json = jsonencode(jsondecode(data.huaweicloud_cce_addon_template.autoscaler.spec).basic)
    custom_json = jsonencode(merge(
      jsondecode(data.huaweicloud_cce_addon_template.autoscaler.spec).parameters.custom,
      {
        cluster_id = huaweicloud_cce_cluster.cluster.id
        tenant_id = "757db842a9154b7e8e041bf64e2ce417"
        scaleDownEnabled = true
      }
    ))
    flavor_json = jsonencode(jsondecode(data.huaweicloud_cce_addon_template.autoscaler.spec).parameters.flavor1)
  }
}

