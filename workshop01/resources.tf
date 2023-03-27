#IMAGE
resource "docker_image" "bgg-database" {
  name = "chukmunnlee/bgg-database:${var.database_version}"
}

resource "docker_image" "bgg-backend" {
  name = "chukmunnlee/bgg-backend:${var.backend_version}"
}

#STACK
resource "docker_network" "bgg-net" {
  name = "${var.app_nameSpace}-bgg-net"
}

resource "docker_volume" "bgg-vol" {
  name = "${var.app_nameSpace}-bgg-vol"
}

resource "docker_container" "bgg-database" {
  name = "${var.app_nameSpace}-bgg-database"
  image = docker_image.bgg-database.image_id
  networks_advanced {
    name = docker_network.bgg-net.id
  }
  ports {
    internal = 3306
    external = 3306
  }
  volumes {
    volume_name = docker_volume.bgg-vol.id
    container_path = "${var.container_path}"
  }
}

resource "docker_container" "bgg-backend" {
  count = var.instance_amount

  name = "${var.app_nameSpace}-bgg-backend-${count.index}"
  image = docker_image.bgg-backend.image_id
  networks_advanced {
    name = docker_network.bgg-net.id
  }
  ports {
    internal = 3000
  }
  env = [
    "BGG_DB_USER=root",
    "BGG_DB_PASSWORD=changeit",
    "BGG_DB_HOST=${docker_container.bgg-database.name}",
  ]
}

resource "local_file" "nginx-conf" {
    filename = "nginx.conf"
    content = templatefile("sample.nginx.conf.tftpl", {
        docker_host = var.docker_host,
        ports = docker_container.bgg-backend[*].ports[0].external
    })
}

data "digitalocean_ssh_key" "aipc" {
    name = var.do_ssh_key
}

resource "digitalocean_droplet" "nginx" {
    name = "nginx"
    image = var.do_image
    region = var.do_region
    size = var.do_size

    ssh_keys = [ data.digitalocean_ssh_key.aipc.id ]

    connection {
      type = "ssh"
      user = "root"
      private_key = file(var.ssh_private_key)
      host = self.ipv4_address
    }

    provisioner "remote-exec" {
        inline = [
            "apt update -y",
            "apt upgrade -y",
            "apt install nginx -y",
        ]
    }
    provisioner "file" {
        source = local_file.nginx-conf.filename
        destination = "/etc/nginx/nginx.conf"
    }
    provisioner "remote-exec" {
        inline = [
          "systemctl restart nginx",
          "systemctl enable nginx",
        ]
    }
}

resource "local_file" "root_at_nginx" {
    filename = "root@${digitalocean_droplet.nginx.ipv4_address}"
    content = ""
    file_permission = "0444"
}

output nginx_ip {
    value = digitalocean_droplet.nginx.ipv4_address
}

output backend_ports {
    value = docker_container.bgg-backend[*].ports[0].external
}